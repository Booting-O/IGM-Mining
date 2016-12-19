% process_qsos: run DLA detection algorithm on specified objects

% load redshifts/DLA flags from training release
prior_catalog = ...
    load(sprintf('%s/catalog', processed_directory(training_release)));

if (ischar(prior_ind))
  prior_ind = eval(prior_ind);
end

prior.z_qsos  = prior_catalog.z_qsos(prior_ind);
prior.dla_ind = prior_catalog.dla_inds(dla_catalog_name);
prior.dla_ind = prior.dla_ind(prior_ind);

% load QSO model from training release
variables_to_load = {'mu', 'M', 'log_sigma', 'rest_wavelengths'};
load(sprintf('%s/learned_qso_model_%s',             ...
             processed_directory(training_release), ...
             training_set_name),                    ...
     variables_to_load{:});

% load DLA samples from training release
variables_to_load = {'offset_samples', 'log_nhi_samples', 'nhi_samples'};
load(sprintf('%s/dla_samples', processed_directory(training_release)), ...
     variables_to_load{:});

% load redshifts from catalog to process
catalog = load(sprintf('%s/catalog', processed_directory(release)));

% load preprocessed QSOs
variables_to_load = {'all_wavelengths', 'all_flux', 'all_noise_variance', ...
                     'all_pixel_mask'};
load(sprintf('%s/preloaded_qsos', processed_directory(release)), ...
     variables_to_load{:});

% enable processing specific QSOs via setting to_test_ind
if (ischar(test_ind))
  test_ind = eval(test_ind);
end

all_wavelengths    =    all_wavelengths(test_ind);
all_flux           =           all_flux(test_ind);
all_noise_variance = all_noise_variance(test_ind);
all_pixel_mask     =     all_pixel_mask(test_ind);

z_qsos = catalog.z_qsos(test_ind);

num_quasars = numel(z_qsos);

% preprocess model interpolants
mu_interpolator = ...
    griddedInterpolant(rest_wavelengths,        mu,        'linear');
M_interpolator = ...
    griddedInterpolant({rest_wavelengths, 1:k}, M,         'linear');
log_sigma_interpolator = ...
    griddedInterpolant(rest_wavelengths,        log_sigma, 'linear');

% initialize results
min_z_dlas                 = nan(num_quasars, 1);
max_z_dlas                 = nan(num_quasars, 1);
log_priors_no_dla          = nan(num_quasars, 1);
log_priors_dla             = nan(num_quasars, 1);
log_likelihoods_no_dla     = nan(num_quasars, 1);
sample_log_likelihoods_dla = nan(num_quasars, num_dla_samples);
log_likelihoods_dla        = nan(num_quasars, 1);
log_posteriors_no_dla      = nan(num_quasars, 1);
log_posteriors_dla         = nan(num_quasars, 1);

for quasar_ind = 1:num_quasars
  tic;

  z_qso = z_qsos(quasar_ind);

  fprintf('processing quasar %i/%i (z_QSO = %0.4f) ...', ...
         quasar_ind, num_quasars, z_qso);

  this_wavelengths    =    all_wavelengths{quasar_ind};
  this_flux           =           all_flux{quasar_ind};
  this_noise_variance = all_noise_variance{quasar_ind};
  this_pixel_mask     =     all_pixel_mask{quasar_ind};

  % convert to QSO rest frame
  this_rest_wavelengths = emitted_wavelengths(this_wavelengths, z_qso);

  ind = (this_rest_wavelengths >= min_lambda) & ...
        (this_rest_wavelengths <= max_lambda) & ...
        (~this_pixel_mask);

  this_wavelengths      =      this_wavelengths(ind);
  this_rest_wavelengths = this_rest_wavelengths(ind);
  this_flux             =             this_flux(ind);
  this_noise_variance   =   this_noise_variance(ind);

  % DLA existence prior
  less_ind = (prior.z_qsos < (z_qso + prior_z_qso_increase));

  this_num_dlas    = nnz(prior.dla_ind(less_ind));
  this_num_quasars = nnz(less_ind);
  this_p_dla = this_num_dlas / this_num_quasars;

  log_priors_dla(quasar_ind) = ...
      log(                   this_num_dlas) - log(this_num_quasars);
  log_priors_no_dla(quasar_ind) = ...
      log(this_num_quasars - this_num_dlas) - log(this_num_quasars);

  fprintf_debug('\n');
  fprintf_debug(' ...     p(   DLA | z_QSO)        : %0.3f\n',     this_p_dla);
  fprintf_debug(' ...     p(no DLA | z_QSO)        : %0.3f\n', 1 - this_p_dla);

  % interpolate model onto given wavelengths
  this_mu = mu_interpolator( this_rest_wavelengths);
  this_M  =  M_interpolator({this_rest_wavelengths, 1:k});

  this_log_sigma = log_sigma_interpolator(this_rest_wavelengths);
  this_sigma2 = exp(2 * this_log_sigma);

  % baseline: probability of no DLA model
  log_likelihoods_no_dla(quasar_ind) = ...
      log_mvnpdf_low_rank(this_flux, this_mu, this_M, ...
          this_sigma2 + this_noise_variance);
  log_posteriors_no_dla(quasar_ind) = ...
      log_priors_no_dla(quasar_ind) + log_likelihoods_no_dla(quasar_ind);

  fprintf_debug(' ... log p(D | z_QSO, no DLA)     : %0.2f\n', ...
                log_likelihoods_no_dla(quasar_ind));

  min_z_dlas(quasar_ind) = min_z_dla(this_wavelengths, z_qso);
  max_z_dlas(quasar_ind) = max_z_dla(this_wavelengths, z_qso);

  sample_z_dlas = ...
       min_z_dlas(quasar_ind) +  ...
      (max_z_dlas(quasar_ind) - min_z_dlas(quasar_ind)) * offset_samples;

  % compute probabilities under DLA model for each of the sampled
  % (normalized offset, log(N HI)) pairs
  parfor i = 1:num_dla_samples
    % absorption corresponding to this sample
    absorption = ...
        voigt(this_wavelengths, sample_z_dlas(i), nhi_samples(i), ...
              num_lines);

    dla_mu     = this_mu .* absorption;
    dla_M      = bsxfun(@times, absorption, this_M);
    dla_sigma2 = this_sigma2 .* absorption.^2;

    sample_log_likelihoods_dla(quasar_ind, i) = ...
        log_mvnpdf_low_rank(this_flux, dla_mu, dla_M, ...
            dla_sigma2 + this_noise_variance);
  end

  % compute sample probabilities and log likelihood of DLA model in
  % numerically safe manner
  max_log_likelihood = max(sample_log_likelihoods_dla(quasar_ind, :));

  sample_probabilities = ...
      exp(sample_log_likelihoods_dla(quasar_ind, :) - ...
          max_log_likelihood);

  log_likelihoods_dla(quasar_ind) = ...
      max_log_likelihood + log(mean(sample_probabilities));

  log_posteriors_dla(quasar_ind) = ...
      log_priors_dla(quasar_ind) + log_likelihoods_dla(quasar_ind);

    fprintf_debug(' ... log p(D | z_QSO,    DLA)     : %0.2f\n', ...
                  log_likelihoods_dla(quasar_ind));
    fprintf_debug(' ... log p(DLA | D, z_QSO)        : %0.2f\n', ...
                  log_posteriors_dla(quasar_ind));

  fprintf(' took %0.3fs.\n', toc);
end

% compute model posteriors in numerically safe manner
max_log_posteriors = ...
    max([log_posteriors_no_dla, log_posteriors_dla], [], 2);

model_posteriors = ...
    exp(bsxfun(@minus, ...
               [log_posteriors_no_dla, log_posteriors_dla], ...
               max_log_posteriors));

model_posteriors = ...
    bsxfun(@times, model_posteriors, 1 ./ sum(model_posteriors, 2));

p_no_dlas = model_posteriors(:, 1);
p_dlas    = 1 - p_no_dlas;

% save results
variables_to_save = {'training_release', 'training_set_name', ...
                     'dla_catalog_name', 'prior_ind', 'release', ...
                     'test_set_name', 'test_ind', 'prior_z_qso_increase', ...
                     'max_z_cut', 'num_lines', 'min_z_dlas', 'max_z_dlas', ...
                     'log_priors_no_dla', 'log_priors_dla', ...
                     'log_likelihoods_no_dla', 'sample_log_likelihoods_dla', ...
                     'log_likelihoods_dla', 'log_posteriors_no_dla', ...
                     'log_posteriors_dla', 'model_posteriors', 'p_no_dlas', ...
                     'p_dlas'};

filename = sprintf('%s/processed_qsos_%s', ...
                   processed_directory(release), ...
                   test_set_name);

save(filename, variables_to_save{:}, '-v7.3');
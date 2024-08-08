fprintf('Setting parameters ...\n')
set_parameters_dr7;

num_C4_samples = 10000;
cataloging = 0;
preloading = 0;
learning   = 0;
sampling   = 0;
plotting   = 0;
processing = 0;
merging    = 0;
EWer       = 0;
pltP       = 0;
CredInt    = 0;
statTesting = 0;
dv_mask    = 350;
HPCC = 0;
voigtPrep = 1;
maskType = 1;
priorType = 1;
ind_S=1;
num_quasars =5000;
saving=1;
fprintf('testing set name: %s\ntraining set name: %s\n', testing_set_name,...
      training_set_name);

fprintf('Building catalogs ...\n')
if cataloging==1
    build_catalog_dr7;
end
variables_to_load= {'all_plate_dr7', 'all_mjd_dr7', 'all_fiber_dr7', ...
'all_QSO_ID', 'all_RA', 'all_DEC', 'all_zqso', 'all_EW1', 'all_errEW1', ...
'all_N_civ','all_z_civ1', 'all_z_civ2', 'all_z_civ3', 'all_RATING', 'c4_QSO_ID'};
load(sprintf('%s/catalog', processed_directory(release)), ...
    variables_to_load{:});
fprintf('Preloading QSOs ...\n')
if preloading==1
    preload_qsos_dr7
end
load(sprintf('%s/preloaded_qsos_%s.mat', processed_directory(release), training_set_name));

fprintf('preparing voigt.c ...\n')

if voigtPrep == 1 
    cd minFunc_2012
    addpath(genpath(pwd))
    mexAll
    cd ..
    if HPCC == 1
        mex voigt_iP.c -lcerf -I/rhome/rmona003/bin/include/ -L/rhome/rmona003/bin/lib64/ 
        mex voigt_iP_fixS.c -lcerf -I/rhome/rmona003/bin/include/ -L/rhome/rmona003/bin/lib64/ 
        % mex voigt0.c -lcerf -I/rhome/rmona003/bin/include/ -L/rhome/rmona003/bin/lib64/ 
    else 
        mex voigt_iP.c -lcerf
        mex voigt_iP_1.c -lcerf
        % mex voigt_iP_fixS.c -lcerf
    end
end
fprintf('preparing testing, training, and prior indeces ...\n')
if learning==1
    half_ID = randsample(all_QSO_ID, int32(train_ratio*numel(all_QSO_ID)));
    test_ind = (~ismember(all_QSO_ID, half_ID)) & (filter_flags==0);
    prior_ind = ismember(all_QSO_ID, half_ID) & (filter_flags==0);
        
    % ind_RATING = filter_flags>10; % initializing with a all false array 
    % for i=1:length(ind_RATING)
        % if ~any(all_RATING(i,:)>=0)
            % ind_RATING(i)=true;
        % end
    % end
    train_ind = (~ismember(all_QSO_ID, c4_QSO_ID) & (filter_flags==0) & ...
    ismember(all_QSO_ID, half_ID) );

    fprintf('Learning model ...\n')
% load preprocessed QSOs
    preloaded_qsos_cat_name= sprintf('%s/preloaded_qsos_%s.mat',... 
                               processed_directory(release), training_set_name);
    learn_qso_model
end

if learning == 2 % --> full learning 
    fprintf('Learning model on the full catalog ...\n')
    preloaded_qsos_cat_name= sprintf('%s/preloaded_qsos_%s.mat',... 
                               processed_directory(release), training_set_name);
    learn_qso_model
end

variables_to_load = {'release', 'train_ind', 'max_noise_variance', ...
                   'minFunc_options', 'rest_wavelengths', 'mu', ...
                    'initial_M', 'M',  'log_likelihood', 'test_ind',...
                    'prior_ind' };

load(sprintf('%s/learned_model-%s.mat', processed_directory(release), training_set_name), variables_to_load{:});

fprintf('Generating samples for integrating out parameters in the model...\n');

if sampling==1
    generate_c4_samples
end

variables_to_load = {'offset_z_samples', 'offset_sigma_samples'
                     'log_nciv_samples', 'nciv_samples'};

load(sprintf('%s/civ_samples_%s.mat', processed_directory(release), sample_name), variables_to_load{:});

fprintf(sprintf('%d Samples are generated\n', num_C4_samples));

% load preprocessed QSOs
variables_to_load = {'all_wavelengths', 'all_flux', 'all_noise_variance', ...
    'all_pixel_mask', 'all_sigma_pixel'};
load(sprintf('%s/preloaded_qsos_%s.mat', processed_directory(release), training_set_name), ...
    variables_to_load{:});
% 

% % % 
if processing==1
    parpool('local', 6);
    % SingleLineModel = 1;

    process_qsos_dr7
end

if statTesting==1
	statTest
end

if EWer==1
    EWer_dr7
end

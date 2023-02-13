Detecting CIV absorbers in SDSS Spectra 
==============================================

This code repository contains code to completely reproduce the aborber 
properties detected in: 

> Reza Mondai, Ming-Feng Ho, Simeon Bird, Kathy Cooksy 
> Detecting CIV absorbers in SDSS DR12 using Gaussian Processes. [arXiv:???
> [astro-ph.GA]](https://arxiv.org/abs/???.???),

The pipeline has multiple stages, outlined and documented below.

Downloading required data
----------------------------------------

The first step of the process is to load the DR12Q quasar catalog and
DR7 CIV catalog, extract some basic data such as redshift,
coordinates, etc., and apply some basic filtering to the spectra:

* spectra with z <  1.7 are filtered
* spectra identified in a visual survey to have broad absorption line
  (BAL) features are filtered
 

Relevant parameters in `set_parameters_dr12.m` that can be tweaked if desired:

    % preprocessing parameters
    dlambda            = 0.5;                    % separation of wavelength grid      Å
    k                  = 20;                      % rank of non-diagonal contribution
    nAVG               = 20;                     % number of points added between two 
                                            % observed wavelengths to make the Voigt finer
    num_C4_samples           = 10000;                  % number of parameter samples
    alpha                    = 0.90;                    % weight of KDE component in mixture
                                                   
    max_civ = 7;  % maximum number of searches per spectrum for CIV absorbers
    dv_mask = 350; % In (km/s), the size of masking window 

This process proceeds in three steps, alternating between the shell
and MATLAB.

First we download the DR7 catalog from [DR7 CIV catlog](
http://guavanator.uhh.hawaii.edu/~kcooksey/SDSS/CIV/data/sdss_civ_cookseyetal13_update1.fit.gz).

Then we load these catalogs into MATLAB:

    % in MATLAB
    set_parameters;
    build_catalogs_dr7;

The `build_catalogs` script will produce a file called `file_list` in
the `data/dr7/spectra` directory containing relative paths to
yet-unfiltered SDSS spectra for download. The `file_list` output is
available in this repository in the same location. The next step is to
download the coadded "speclite" SDSS spectra for these observations
(warning: total download is 35 GB). The `download_spectra.sh` script
requires `wget` to be available. On OS X systems, this may be
installed easily with [Homebrew](http://brew.sh/index.html).

    # in shell
    cd data/scripts
    ./download_spectra.sh

`download_spectra.sh` will download the observational data for the yet
unfiltered lines of sight to the `data/dr12q/spectra` directory.

Loading and preprocessing spectra
---------------------------------

Now we load these data. Spectra with fewer than 400 nonmasked pixels are filtered.

Relevant parameters in `set_parameters` that can be tweaked if
desired:

    % preprocessing parameters
    min_num_pixels = 400;                         % minimum number of non-masked pixels

When ready, the MATLAB code to preload the spectra is:

    set_parameters;
    release = 'dr12q';

    file_loader = @(plate, mjd, fiber_id) ...
      (read_spec(sprintf('%s/%i/spec-%i-%i-%04i.fits', ...
        spectra_directory(release),                  ...
        plate,                                       ...
        plate,                                       ...
        mjd,                                         ...
        fiber_id)));

    preload_qsos;

The result will be a completed catalog data file,
`data/[release]/processed/zqso_only_catalog.mat`, with complete filtering
information and a file containing preloaded and preprocessed data for
the 158821 nonfiltered spectra,
`data/[release]/processed/preloaded_zqso_only_qsos.mat`.

Building GP models for quasar spectra
-------------------------------------

Now we build our models, including our Gaussian process null model for
quasar emission spectra.

To build the null model for quasar emission spectra, we need to
indicate a set of spectra to use for training. Here we select all
spectra in DR9 and not removed by our filtering steps.

These particular choices may be accomplished with:

    training_release  = 'dr12q';
    train_ind = ...
        [' catalog.in_dr9                     & ' ...
         '(catalog.filter_flags == 0) ' ];

After specifying the spectra to use in `training_release` and
`train_ind`, we call `learn_qso_model` to learn the model.
To learn the model, you will need the MATLAB toolbox
[minFunc](https://www.cs.ubc.ca/~schmidtm/Software/minFunc.html)
available from Mark Schmidt.

You should cd to the directory where you installed minFunc to and run:

    addpath(genpath(pwd));
    mexAll;

to initialize minFunc before the first time you use it.

Relevant parameters in `set_parameters` that can be tweaked if
desired:

    % null model parameters
    min_lambda         =  910;                 % range of rest wavelengths to       Å
    max_lambda         = 3000;                 %   model
    dlambda            =    0.25;                 % separation of wavelength grid      Å
    k                  = 20;                      % rank of non-diagonal contribution
    max_noise_variance = 4^2;                     % maximum pixel noise allowed during model training

    % optimization parameters
    minFunc_options =               ...           % optimization options for model fitting
        struct('MaxIter',     4000, ...
               'MaxFunEvals', 8000);

When ready, the MATLAB code to learn the null quasar emission model
is:

    training_set_name = 'dr9q_minus_concordance';
    learn_qso_model;

The learned qso model is stored in
`data/[training_release]/processed/learned_zqso_only_model_outdata_normout_[training_set_name]_norm_[normalization_min_lambda]-[normalization_max_lambda].mat`.

Processing spectra for Redshift Estimation
------------------------------------

Finally, we may use our built model to compute the posterior
probability of the quasar redshift as described
in the paper above.

We must specify a few things first. First, we
must specify which quasar emission model to use; to select the one
learned above, we may use

    % specify the learned quasar model to use
    training_release  = 'dr12q';
    training_set_name = 'dr9q_minus_concordance';

(the code will attempt to load the model from a file called
`data/[training_release]/processed/learned_zqso_only_model_outdata_normout_[training_set_name]_norm_[normalization_min_lambda]-[normalization_max_lambda].mat`.)

Next, we must specify which spectra to process. Here we use
all DR12Q spectra that were not filtered:

    % specify the spectra to process
    release = 'dr12q';
    test_set_name = 'dr12q';
    test_ind = '(catalog.filter_flags == 0)';

When ready, the selected spectra can be processed with `process_qsos`.
Relevant parameters in `set_parameters` that can be tweaked if
desired:

    num_zqso_samples     = 10000;                  % number of parameter samples

This script will write the results in
`data/[release]/processed_qsos_[test_set_name].mat`.

The complete code for processing the spectra in MATLAB is:

    % produce catalog 
    set_parameters;

    % specify the learned quasar model to use
    training_release  = 'dr12q';
    training_set_name = 'dr9q_minus_concordance';

    % specify the spectra to process
    release = 'dr12q';
    test_set_name = 'dr12q';
    test_ind = '(catalog.filter_flags == 0)';

    % process the spectra
    process_qsos;

Finally, we may create an ASCII catalog of the results if desired with
`generate_ascii_catalog`, e.g.:

    set_parameters;
    training_release  = 'dr12q';
    release = 'dr12q';
    test_set_name = 'dr12q';

    generate_ascii_catalog;

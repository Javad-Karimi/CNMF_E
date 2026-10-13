tic

root_path = 'C:\Users\Javad\Data\CA1_project\testing_CNMFE_batch_with_SFP_initialization_5\linear_track\';

% session_paths = {'PRE_POST\JKA-HPC-09\2025_07_15\10_08_21\Miniscope\15-Jul-2025_21-37-36', ...
%                  'RUN\JKA-HPC-09\2025_07_15\14_28_38\Miniscope\15-Jul-2025_22-23-36', ...
%                  'PRE_POST\JKA-HPC-09\2025_07_15\15_01_06\Miniscope\15-Jul-2025_21-9-58', ...
%                  'RUN\JKA-HPC-09\2025_07_15\18_08_05\Miniscope\15-Jul-2025_22-23-38'};
session_paths = {'PRE_POST\JKA-HPC-09\2025_07_15\10_08_21\Miniscope\15-Jul-2025_21-37-36', ...
                 'RUN\JKA-HPC-09\2025_07_15\14_28_38\Miniscope\15-Jul-2025_22-23-36'};

% put all file names into a cell array with th eorder you want CNMFE go through; when it's empty, manually select files 
session_paths = cellfun(@(x) fullfile(root_path, x, 'shortend_msvideo.avi'), session_paths, 'UniformOutput', false);

reference_session_id = 1; % reference session for registration
Fs = 30;             % frame rate
tsub = 2;           % temporal downsampling factor % changed with respect to Quinn's version
%%
[tforms, Rfixed] = register_sessions(session_paths, reference_session_id);
%%
neuron = Sources2D(); 
nams = neuron.select_multiple_files(session_paths);  %if nam is [], then select data interactively 
%% parameters
% -------------------------    COMPUTATION    -------------------------  %
pars_envs = struct('memory_size_to_use', 45, ...   % GB, memory space you allow to use in MATLAB
    'memory_size_per_patch', 2, ...   % GB, space for loading data within one patch
    'patch_dims', [10, 10], ...
    'batch_frames', 4 * 60 * 60 * round(Fs/tsub));  %GB, patch size
% pars_envs = struct('memory_size_to_use', 45, ...   % GB, memory space you allow to use in MATLAB
%     'memory_size_per_patch', 25, ...   % GB, space for loading data within one patch
%     'patch_dims', [10, 10], ...
%     'batch_frames', 1000);  %GB, patch size
% -------------------------      SPATIAL      -------------------------  %
include_residual = false; % If true, look for neurons in the residuals
gSig = 4;           % pixel, gaussian width of a gaussian kernel for filtering the data. 0 means no filtering %3 %15
gSiz = 15;          % pixel, neuron diameter
ssub = 1;           % spatial downsampling factor
with_dendrites = true;   % with dendrites or not
if with_dendrites
    % determine the search locations by dilating the current neuron shapes
    updateA_search_method = 'dilate';  %#ok<UNRCH>
    updateA_bSiz = 5;
    updateA_dist = neuron.options.dist;
else
    % determine the search locations by selecting a round area
    updateA_search_method = 'ellipse'; %#ok<UNRCH>
    updateA_dist = 5;
    updateA_bSiz = neuron.options.dist;
end
spatial_constraints = struct('connected', true, 'circular', false);  % you can include following constraints: 'circular'
spatial_algorithm = 'hals_thresh';

% -------------------------      TEMPORAL     -------------------------  %
% Fs = 30;             % frame rate
% tsub = 2;           % temporal downsampling factor % changed with respect to Quinn's version
deconv_flag = false; % Perform deconvolution
deconv_options = struct('type', 'ar1', ... % model of the calcium traces. {'ar1', 'ar2'}
    'method', 'constrained', ... % method for running deconvolution {'foopsi', 'constrained', 'thresholded'}
    'smin', -5, ...         % minimum spike size. When the value is negative, the actual threshold is abs(smin)*noise level
    'optimize_pars', true, ...  % optimize AR coefficients
    'optimize_b', true, ...% optimize the baseline);
    'max_tau', 100);    % maximum decay time (unit: frame);

nk = 3;             % detrending the slow fluctuation. usually 1 is fine (no detrending)
% when changed, try some integers smaller than total_frame/(Fs*30)
detrend_method = 'spline';  % compute the local minimum as an estimation of trend.

% -------------------------     BACKGROUND    -------------------------  %
bg_model = 'ring';  % model of the background {'ring', 'svd'(default), 'nmf'}
nb = 1;             % number of background sources for each patch (only be used in SVD and NMF model)
ring_radius = 18;  % when the ring model used, it is the radius of the ring used in the background model.
%otherwise, it's just the width of the overlapping area
num_neighbors = []; % number of neighbors for each neuron

% -------------------------      MERGING      -------------------------  %
show_merge = false;  % if true, manually verify the merging step
merge_thr = 0.65;     % thresholds for merging neurons; [spatial overlap ratio, temporal correlation of calcium traces, ...
% spike correlation]
method_dist = 'max';   % method for computing neuron distances {'mean', 'max'}
dmin = 5;       % minimum distances between two neurons. it is used together with merge_thr
dmin_only = 2;  % merge neurons if their distances are smaller than dmin_only.
merge_thr_spatial = [0.8, 0.4, -inf];  % merge components with highly correlated spatial shapes (corr=0.8) and ...
% small temporal correlations (corr=0.1)

% -------------------------  INITIALIZATION   -------------------------  %
K = [];             % maximum number of neurons per patch. when K=[], take as many as possible.
min_corr = 0.8;     % minimum local correlation for a seeding pixel, default 0.8
min_pnr = 8;       % minimum peak-to-noise ratio for a seeding pixel
min_pixel = gSig^2;      % minimum number of nonzero pixels for each neuron
bd = 0;             % number of rows/columns to be ignored in the boundary (mainly for motion corrected data)
frame_range = [];   % when [], uses all frames
save_initialization = false;    % save the initialization procedure as a video.
use_parallel = true;    % use parallel computation for parallel computing
show_init = false;   % show initialization results
choose_params = false; % manually choose parameters
center_psf = true;  % set the value as true when the background fluctuation is large (usually 1p data)
% set the value as false when the background fluctuation is small (2p)

% -------------------------  Residual   -------------------------  %
min_corr_res = 0.8; % Default 0.7
min_pnr_res = 8;
seed_method_res = 'auto';  % method for initializing neurons from the residual
update_sn = true;

% ----------------------  WITH MANUAL INTERVENTION  --------------------  %
with_manual_intervention = false;

% -------------------------    UPDATE ALL    -------------------------  %
neuron.updateParams('gSig', gSig, ...       % -------- spatial --------
    'gSiz', gSiz, ...
    'ring_radius', ring_radius, ...
    'ssub', ssub, ...
    'search_method', updateA_search_method, ...
    'bSiz', updateA_bSiz, ...
    'dist', updateA_bSiz, ...
    'spatial_constraints', spatial_constraints, ...
    'spatial_algorithm', spatial_algorithm, ...
    'tsub', tsub, ...                       % -------- temporal --------
    'deconv_flag', deconv_flag, 'deconv_options', deconv_options, ...
    'nk', nk, ...
    'detrend_method', detrend_method, ...
    'background_model', bg_model, ...       % -------- background --------
    'nb', nb, ...
    'ring_radius', ring_radius, ...
    'num_neighbors', num_neighbors, ...
    'merge_thr', merge_thr, ...             % -------- merging ---------
    'dmin', dmin, ...
    'method_dist', method_dist, ...
    'min_corr', min_corr, ...               % ----- initialization -----
    'min_pnr', min_pnr, ...
    'min_pixel', min_pixel, ...
    'bd', bd, ...
    'center_psf', center_psf);
neuron.Fs = Fs;
neuron.options.save_intermediate = 1;            
%% distribute data and be ready to run source extraction 
neuron.getReady_batch(pars_envs, [], tforms, Rfixed, reference_session_id); 
% neuron.getReady_batch(pars_envs, []); 
%%
% load('Y:\javad.karimi\CA1_project\preprocessed_data\linear_track\RUN\JKA-HPC-09\2025_07_15\14_28_38\Miniscope\SFP.mat');
% load('Y:\javad.karimi\CA1_project\preprocessed_data\linear_track\RUN\JKA-HPC-09\2025_07_15\14_28_38\Miniscope\SFP_mask.mat');
% SFP = SFP(SFP_mask, :, :);
% SFP = permute(SFP, [2,3,1]); % initial_A (SFPs) must be d1*d2-by-K (300*300-by-neuron#)
% % load('d:\CA1_project\preprocessed_data\linear_track\RUN\JKA-HPC-09\2025_07_15\14_28_38\Miniscope\ms.mat', 'SFPs');
% % SFP = SFPs; % initial_A (SFPs) must be d1*d2-by-K (300*300-by-neuron#)
% SFP_registered = SFP;
% for sfp_counter = 1:size(SFP, 3)
%     SFP_registered(:,:,sfp_counter) = imwarp(squeeze(SFP(:,:,sfp_counter)), tforms{1}, "OutputView", Rfixed);
% end
%% initialize neurons in batch mode; took 23 minutes to run for 4 X 5 min sessions 
% tic
% neuron.initComponents_batch_with_initial_A(K, false, use_parallel, SFP_registered);
neuron.initComponents_batch(K, save_initialization, use_parallel); 
% toc
%% udpate spatial components for all batches; took 86 seconds to run for 4 X 5 min sessions 
% tic
neuron.update_spatial_batch(use_parallel); 
% toc
%% udpate temporal components for all bataches; took 68 seconds to run for 4 X 5 min sessions 
% tic
neuron.update_temporal_batch(use_parallel); 
% toc
%% update background; took 11 minutes to run for 4 X 5 min sessions 
% tic
neuron.update_background_batch(use_parallel); 
% toc
%% TODO: It seems there are more neurons in S than A. Why?
neuron.update_spatial_batch(use_parallel); 
neuron.update_temporal_batch(use_parallel); 
neuron.update_temporal_batch(use_parallel); 
%%
neuron.update_background_batch(use_parallel); 
neuron.update_spatial_batch(use_parallel); 
neuron.update_temporal_batch(use_parallel); 
%% TODO: delete neurons 

%% TODO: merge neurons 

%% get the correlation image and PNR image for all neurons; took 5 minutes to run for 4 X 5 min sessions  
% tic
neuron.correlation_pnr_batch(); 
% toc
%% concatenate temporal components; took less than 1 second for 4 X 5 min sessions  
% tic
neuron.concatenate_temporal_batch(); 
% toc
%% TODO: figure out why neuron.options.d1/d2 are empty instead of bein 300.
% neuron.viewNeurons([],neuron.C_raw); 

%% save workspace; took 80 seconds for 4 X 5 min sessions   
% tic
neuron.save_workspace_batch(); 
toc
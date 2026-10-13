function run_CNMFE_with_fixed_SFPs(session_path)
cd(session_path);
% session_path = pwd;

% look for shortend_msvideo.avi or concat.avi in the current directory and subdirectories
session_path = dir('*/msvideo.avi');
shifts = [];
if isempty(session_path)
    session_path = dir('concat.avi');
    if isempty(session_path)
        error('No msvideo.avi or concat.avi found in the current directory or subdirectories');
    end
    load('ms.mat', 'shifts'); % NORMCORRE shifts as a cell array of the size one by number of avi files. 
    %  Each cell contains the shifts for the corresponding avi file as a non-scalar structure.
    % concatenate the shifts into a single structure
    shifts = cat(1, shifts{:});
end
session_path = fullfile(session_path.folder, session_path.name);

% Fs = 30;  % frame rate
% tsub = 2; % temporal downsampling factor
%%
% load('SFP_union.mat', 'SFP', 'tform', 'Rfixed');
neuron = Sources2D();
%%
pars_envs = struct('memory_size_to_use', 100, ...   % GB, memory space you allow to use in MATLAB
    'memory_size_per_patch', 20, ...   % GB, space for loading data within one patch
    'patch_dims', [10, 10]);  %GB, patch size
% pars_envs = struct('memory_size_to_use', 45, ...   % GB, memory space you allow to use in MATLAB
%     'memory_size_per_patch', 25, ...   % GB, space for loading data within one patch
%     'patch_dims', [10, 10]);  %GB, patch size
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
Fs = 30;             % frame rate
tsub = 2;           % temporal downsampling factor % changed with respect to Quinn's version
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
%% 
neuron.select_data(session_path);
%%
% neuron.getReady(pars_envs, [], tform, Rfixed);
neuron.getReady(pars_envs, [], shifts);
% neuron.getReady(pars_envs, []);
%% Initialize temporal components using the fixed spatial components patch by patch
load('SFP_union.mat', 'SFP');
SFP = permute(SFP, [2,3,1]);
% fixed_A must be d1*d2-by-K (300*300-by-neuron#)
fixed_A = reshape(SFP, size(SFP,1)*size(SFP,2), []);
fixed_A = double(fixed_A > 0);
neuron.initComponents_parallel_with_initial_A(fixed_A);
%% 
neuron.update_background_parallel(true);
neuron.options.maxIter = 10;
neuron.update_temporal_parallel(true, true);
neuron.update_temporal_parallel(true, true);

neuron.update_background_parallel(true);
neuron.update_temporal_parallel(true, true);
neuron.update_temporal_parallel(true, true);

neuron.update_background_parallel(true);
neuron.update_temporal_parallel(true, true);
neuron.update_temporal_parallel(true, true);
% toc
% [neuron.Cn, neuron.PNR] = neuron.correlation_pnr_parallel();

ms.Options = neuron.options;
% ms.Centroids = center;
% ms.CorrProj = neuron.Cn;
% ms.PeakToNoiseProj = neuron.PNR;

ms.FiltTraces = neuron.C';
% ms.RawTraces = neuron.C_raw';
ms.SFPs = neuron.reshape(neuron.A, 2);
% ms.numNeurons = size(ms.SFPs,3);

save('ms_union.mat', '-struct', 'ms', '-v7.3'); 
end
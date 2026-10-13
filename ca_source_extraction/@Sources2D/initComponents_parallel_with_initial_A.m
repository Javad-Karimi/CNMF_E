function initComponents_parallel_with_initial_A(obj, SFP, varargin)
% initial_A must be d1*d2-by-K (300*300-by-neuron#)
if size(SFP, 3) > 1
    initial_A = reshape(SFP, size(SFP,1)*size(SFP,2), []);
else
    initial_A = SFP;
end
initial_A = sparse(initial_A);

if ~isempty(varargin)
    background_init_flag = varargin{1};
else
    background_init_flag = true;
end
%%
% Assign the predefined spatial components
obj.A = initial_A;
%% Initialize temporal components using the fixed spatial components patch by patch
mat_data = obj.P.mat_data;
patch_pos = mat_data.patch_pos;
block_pos = mat_data.block_pos;

dims = mat_data.dims;
d1 = dims(1);
d2 = dims(2);
T = dims(3);

% frames to be loaded for initialization
if ~exist('frame_range', 'var')
    frame_range = obj.frame_range;
end

if isempty(frame_range)
    frame_range = [1, T];
else
    frame_range(frame_range<1) = 1;
    frame_range(frame_range>T) = T;
end

try 
    temp_var = zeros(1, 1, diff(frame_range) + 1);
catch ME
    frame_range = fix(frame_range);
end

T = diff(frame_range) + 1;
obj.frame_range = frame_range;

K = size(obj.A, 2);
%% initializing the calium traces for each SFP; takes around 164 seconds for a RUN sesssions
C_patch = cell(size(patch_pos));
ind_patch_neuron = cell(size(patch_pos));

parfor mpatch = 1:numel(patch_pos)
    % tmp_block = block_pos{mpatch};
    tmp_patch = patch_pos{mpatch};

    % Pixels in the block used to associate ROIs with this patch.
    mask = false(d1, d2);
    % mask(tmp_block(1):tmp_block(2), tmp_block(3):tmp_block(4)) = true;
    mask(tmp_patch(1):tmp_patch(2), tmp_patch(3):tmp_patch(4)) = true;

    ind = (reshape(mask, 1, []) * obj.A > 0);
    ind = logical(ind);

    ind_patch_neuron{mpatch} = find(ind);

    if ~any(ind)
        C_patch{mpatch} = [];
        continue;
    end

    % Load this patch from CNMF-E's memory-mapped data.
    Ypatch = get_patch_data( ...
        mat_data, tmp_patch, obj.frame_range, false);
    d1_patch = size(Ypatch,1);
    d2_patch = size(Ypatch,2);

    Ypatch = double(reshape(Ypatch, [], size(Ypatch, 3)));

    if obj.options.nk>1
        Ypatch_dt = detrend_data(Ypatch, obj.options.nk, obj.options.detrend_method); % detrend data
    else
        Ypatch_dt = Ypatch;
    end

    % create a spatial filter for removing background
    if obj.options.gSig>0
        if obj.options.center_psf
            psf = fspecial('gaussian', ceil(obj.options.gSig*4+1), obj.options.gSig);
            ind_nonzero = (psf(:)>=max(psf(:,1)));
            psf = psf-mean(psf(ind_nonzero));
            psf(~ind_nonzero) = 0;
        else
            psf = fspecial('gaussian', round(obj.options.gSiz), obj.options.gSig);
        end
    else
        psf = [];
    end

    % filter the data
    if isempty(psf)
        % no filtering
        HY = Ypatch_dt;
    else
        HY = imfilter(reshape(Ypatch_dt, d1_patch , d2_patch ,[]), psf, 'replicate');
    end

    HY = reshape(HY, d1_patch * d2_patch, []);
    HY = bsxfun(@minus, HY, median(HY, 2));

    % Restrict A to the patch/block.
    A_block = obj.A(mask, ind);
    A_block = double(A_block > 0);
    % denom = sum(A_block.^2, 1)' + eps;
    % ci = bsxfun(@rdivide, A_block' * HY, denom); % neuron by T
    ci = A_block' * HY;
    for ii = 1:size(ci, 1)
        [b, sn] = estimate_baseline_noise(ci(ii, :)');
        psd_sn = GetSn(ci(ii, :)');
        if sn > psd_sn
            sn = psd_sn;
            [ci_temp, ~] = remove_baseline(ci(ii, :)', sn);
            ci(ii, :) = ci_temp';
        else
            ci(ii, :) = ci(ii, :) - b;
        end
    end

    C_patch{mpatch} = ci;
    % ci = mean(HY(SFP_centers(ii), :), 1);

    % % Restrict A to the patch/block.
    % A_block = neuron.A(mask, ind);
    %
    % % Initial nonnegative least-squares-like projection.
    % denom = sum(A_block.^2, 1)' + eps;
    % C_patch{mpatch} = max(0, bsxfun(@rdivide, A_block' * Ypatch, denom));
    % C_patch{mpatch} = ci;
end

% Combine overlapping patch estimates into one K-by-T matrix.
C0 = zeros(K, T);
weight = zeros(K, 1);

for mpatch = 1:numel(C_patch)
    ind = ind_patch_neuron{mpatch};
    if isempty(ind)
        continue;
    end

    Ctmp = C_patch{mpatch};
    % w = sum(Ctmp.^0, 2); %#ok<NASGU> ???????? CHECK THIS LINE

    % Use the number of pixels in the corresponding A support as weights.
    % tmp_block = block_pos{mpatch};
    % mask = false(d1, d2);
    % mask(tmp_block(1):tmp_block(2), tmp_block(3):tmp_block(4)) = true;
    tmp_patch = patch_pos{mpatch};
    mask = false(d1, d2);
    mask(tmp_patch(1):tmp_patch(2), tmp_patch(3):tmp_patch(4)) = true;

    A_block = obj.A(mask, ind);
    A_block = double(A_block > 0);
    % ww = sum(A_block.^2, 1)';
    ww = sum(A_block, 1)';

    C0(ind, :) = C0(ind, :) + bsxfun(@times, Ctmp, ww);
    % C0(ind, :) = C0(ind, :) + Ctmp;
    weight(ind) = weight(ind) + ww;
end

weight(weight == 0) = 1;
C0 = bsxfun(@rdivide, C0, weight);
%%
% deconv_options_0 = neuron.options.deconv_options;
% deconv_flag = options.deconv_flag;
% 
% Cin = zeros(size(C0));
% Sin = zeros(size(C0));
% Cin_raw = zeros(size(C0));
% if deconv_flag
%     deconv the temporal trace
%     parfor ii = 1 : size(C0, 1)
%         [Cin(ii, :), Sin(ii, :), deconv_options] = deconvolveCa(C0(ii, :), deconv_options_0);
%         Cin_raw(ii, :) = C0(ii, :) - deconv_options.b;
%     end
% 
%     % kernel_pars(k, :) = kernel.pars;
%     kernel_pars{k} = reshape(deconv_options.pars, 1, []);
% else
%     ci = ci_raw;
%     Cin = C0;
%     Cin_raw = C0;
% end
%%
obj.C = C0;
% obj.C = wdenoise(C0', 2, 'Wavelet', 'sym4', 'DenoisingMethod', 'UniversalThreshold', 'ThresholdRule', 'Soft')';
obj.C_raw = C0;
% neuron.S = zeros(size(C0));
%% Initialize temporal components using the fixed spatial components using the whole data
% K = size(fixed_A, 2);
% T = neuron.P.numFrames;
%
% % Create the required initial temporal matrix.
% % This requires Y to be available as d-by-T data.
% % For large data, use the patch-wise version shown below.
% C0 = fixed_A' * double(Y);
% C0 = bsxfun(@rdivide, C0, sum(fixed_A.^2, 1)' + eps);
% C0 = max(C0, 0);
%
% neuron.C = C0;
% neuron.C_raw = C0;
% neuron.S = zeros(size(C0));
% % %%
% % tic
% %
% % % The third argument enables patch-level parallel processing.
% % neuron.initTemporal([], true);
% % toc
%% preallocate spaces for saving model variables relating to background components
[nr_patch, nc_patch] = size(patch_pos);
if background_init_flag
    bg_model = obj.options.background_model;
    bg_ssub = obj.options.bg_ssub;
    W = cell(nr_patch, nc_patch);    % matrix for saving the weight matrix within each block
    b0 = cell(nr_patch, nc_patch);   % constant baselines for all pixels
    b = cell(nr_patch, nc_patch);
    f = cell(nr_patch, nc_patch);

    if strcmpi(bg_model, 'ring')
        rr = ceil(obj.options.ring_radius/bg_ssub);    % radius of the ring
        [r_shift, c_shift] = get_nhood(rr, obj.options.num_neighbors); % shifts used for acquiring the neighboring pixels on the ring
        parfor mpatch=1:(nr_patch*nc_patch)
            tmp_patch = patch_pos{mpatch};    % patch position
            tmp_block = block_pos{mpatch};    % block position
            nr = diff(tmp_patch(1:2)) + 1;
            nc = diff(tmp_patch(3:4)) + 1;
            nr_block = diff(tmp_block(1:2))+1;
            nc_block = diff(tmp_block(3:4))+1;
            b0{mpatch} = zeros(nr*nc, 1);

            if bg_ssub==1
                [csub, rsub] = meshgrid(tmp_patch(3):tmp_patch(4), tmp_patch(1):tmp_patch(2));
                csub = reshape(csub, [], 1);
                rsub = reshape(rsub, [], 1);
                ii = repmat((1:numel(csub))', [1, length(r_shift)]);
                csub = bsxfun(@plus, csub, c_shift);
                rsub = bsxfun(@plus, rsub, r_shift);
                ind = and(and(csub>=1, csub<=d2), and(rsub>=1, rsub<=d1));
                jj = (csub-tmp_block(3)) * (diff(tmp_block(1:2))+1) + (rsub-tmp_block(1)+1);

                temp = sparse(ii(ind), jj(ind), 1, nr*nc, nr_block*nc_block);
                W{mpatch} = bsxfun(@times, temp, 1./sum(temp, 2));
            else
                d1s = ceil(nr_block/bg_ssub);
                d2s = ceil(nc_block/bg_ssub);

                [csub, rsub] = meshgrid(1:d2s, 1:d1s);
                csub = reshape(csub, [], 1);
                rsub = reshape(rsub, [], 1);
                ii = repmat((1:numel(csub))', [1, length(r_shift)]);
                csub = bsxfun(@plus, csub, c_shift);
                rsub = bsxfun(@plus, rsub, r_shift);
                jj = (csub-1) * d1s + rsub;
                % remove neighbors that are out of boundary
                ind = and(and(csub>=1, csub<=d2s), and(rsub>=1, rsub<=d1s));
                temp = sparse(ii(ind), jj(ind), 1, d1s*d2s, d1s*d2s);
                W{mpatch} = bsxfun(@times, temp, 1./sum(temp, 2));
            end
        end
    elseif strcmpi(bg_model, 'nmf')
        nb = obj.options.nb;
        for mpatch=1:(nr_patch*nc_patch)
            [r, c] = ind2sub([nr_patch, nc_patch], mpatch);   % patch ind
            tmp_patch = patch_pos{r, c};    % patch position
            nr = diff(tmp_patch(1:2)) + 1;
            nc = diff(tmp_patch(3:4)) + 1;
            b{r, c} = zeros(nr*nc, nb);
            f{r, c} = zeros(nb, T);
        end
    else
        %default, SVD model
        nb = obj.options.nb;
        for mpatch=1:(nr_patch*nc_patch)
            [r, c] = ind2sub([nr_patch, nc_patch], mpatch);   % patch ind
            tmp_patch = patch_pos{r, c};    % patch position
            nr = diff(tmp_patch(1:2)) + 1;
            nc = diff(tmp_patch(3:4)) + 1;
            b{r, c} = zeros(nr*nc, nb);
            f{r, c} = zeros(nb, T);
            b0{r, c} = zeros(nr*nc, 1);
        end
    end

    obj.W = W;
    obj.b0 = b0;
    obj.b = b;
    obj.f = f;
    obj.frame_range = round(obj.frame_range);
    clear W b0 b f;    % remove these variables for saving RAM space
end
%%
mat_file = mat_data.Properties.Source;

% folders and files for saving the results
tmp_dir = sprintf('%s%sframes_%d_%d%s', fileparts(mat_file),filesep, frame_range(1), frame_range(2), filesep);
if ~exist(tmp_dir, 'dir')
    mkdir(tmp_dir);
end
log_folder = [tmp_dir,  'LOGS_', get_date(), filesep];
log_file = [log_folder, 'logs.txt'];
log_data_file = [log_folder, 'intermediate_results.mat'];
obj.P.log_folder = log_folder;
obj.P.log_file = log_file;
obj.P.log_data = log_data_file;
if ~exist(log_folder, 'dir')
    mkdir(log_folder);
end
mat_file = matfile(log_file, 'Writable', true);
% save(log_file, 'file_name', '-v7.3');
fclose(fopen(log_file, 'w'));
% log_data = matfile(log_data_file, 'Writable', true);
save(log_data_file, 'log_folder', '-v7.3');
log_data = matfile(log_data_file, 'Writable', true);
log_data.test = 'this is a test';
% fclose(fopen(log_data_file, 'w'));
clearvars log_data mat_file
%%
Ymean = cell(nr_patch, nc_patch);
% if use_parallel
parfor mpatch=1:(nr_patch*nc_patch)
    tmp_patch = patch_pos{mpatch};
    tmp_block = block_pos{mpatch};
    Ypatch = get_patch_data(mat_data, tmp_patch, frame_range, true);
    temp = mean(Ypatch, 3);
    Ymean{mpatch} = temp((tmp_patch(1):tmp_patch(2))-tmp_block(1)+1, (tmp_patch(3):tmp_patch(4))-tmp_block(3)+1);
end
% else
%     for mpatch=1:(nr_patch*nc_patch)
%         tmp_patch = patch_pos{mpatch};
%         tmp_block = block_pos{mpatch};
%         Ypatch = get_patch_data(mat_data, tmp_patch, frame_range, true);
%         temp = mean(Ypatch, 3);
%         Ymean{mpatch} = temp((tmp_patch(1):tmp_patch(2))-tmp_block(1)+1, (tmp_patch(3):tmp_patch(4))-tmp_block(3)+1);
%     end
% end
obj.P.Ymean = Ymean;
%%
if obj.options.deconv_flag
    Sin = cell2mat(reshape(Sin, [], 1));
    kernel_pars = cell2mat(reshape(kernel_pars, [], 1));
    obj.S = sparse(Sin);
    obj.P.kernel_pars = kernel_pars;
else
    obj.S = zeros(size(obj.C));
end
% obj.Cn = Cn;
K = size(obj.A, 2);
obj.P.k_ids = K;
obj.ids = (1:K);
obj.tags = zeros(K,1, 'like', uint16(0));

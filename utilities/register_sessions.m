function [tforms, Rfixed] = register_sessions(session_paths, reference_session_id)

% refFile = session_paths{reference_session_id};
% movFiles = session_paths(setdiff(1:numel(session_paths), reference_session_id));

nRandomFrames = 1000;   % preset number of frames to sample
%%
% Open videos
% session_paths = cat(2, refFile, movFiles);
vid = cell(1, numel(session_paths));
minNumFrames = (20-1) * 60 * 30;  % ~20 minutes at 30 fps
for k = 1:numel(session_paths)
    vid{k} = VideoReader(session_paths{k});
    minNumFrames = min(minNumFrames, vid{k}.NumFrames);
end

if nRandomFrames > minNumFrames
    error("nRandomFrames must be <= the smallest video length.");
end

% Same random frame indices for all files
rng('default');  % For reproducibility

% Registration setup
[optimizer, metric] = imregconfig("monomodal");
optimizer.MaximumIterations = 1000;
% Tune this based on the returned optimizer type:
% For monomodal, inspect properties(optimizer) and adjust step-length settings.
% For multimodal, typical settings are:
% optimizer.InitialRadius = 0.01;
% optimizer.Epsilon = 1e-4;
% optimizer.GrowthFactor = 1.01;
% optimizer.MaximumIterations = 300;

refFrames = zeros(vid{1}.Height, vid{1}.Width, nRandomFrames, "uint8");
movFrames = cell(numel(session_paths), 1);
for m = 1:numel(session_paths)
    if m ~= reference_session_id
        movFrames{m} = zeros(vid{m}.Height, vid{m}.Width, nRandomFrames, "uint8");
    end

    frameIdx = sort(randperm(vid{m}.NumFrames, nRandomFrames));

    for f = 1:nRandomFrames
        idx = frameIdx(f);
        if m == reference_session_id
            refFrame = readGrayFrame(vid{m}, idx);
            refFrames(:,:,f) = refFrame;
        else
            movFrame = readGrayFrame(vid{m}, idx);
            movFrames{m}(:,:,f) = movFrame;
        end
    end
end
%%
refFrame = mean(refFrames, 3, "native");
movFrames = cellfun(@(x) mean(x, 3, "native"), movFrames, "UniformOutput", false);
%% min-max normalize each frame to [0, 1] for better registration performance
refFrame = mat2gray(refFrame);
% refFrame = mat2gray(refFrame, [min(refFrame(:)), max(refFrame(:))]);
for m = 1:numel(session_paths)
    if m ~= reference_session_id
        movFrames{m} = mat2gray(movFrames{m});
    else
        movFrames{m} = nan;  % No need to normalize the reference frame    
    end
end
%% crop the frames to remove black borders (if any) for better registration performance
% % Define the cropping rectangle [x, y, width, height]
% cropRect = [80, 80, 120, 120];  % Adjust these values based on your specific video content
% refFrame_cropped = refFrame(cropRect(2):cropRect(2) + cropRect(4) - 1, cropRect(1):cropRect(1) + cropRect(3) - 1);
% movFrames_cropped = cell(size(movFrames));
% for m = 1:numel(session_paths)
%     if m ~= reference_session_id
%         movFrames_cropped{m} = movFrames{m}(cropRect(2):cropRect(2) + cropRect(4) - 1, cropRect(1):cropRect(1) + cropRect(3) - 1);
%     else
%         movFrames_cropped{m} = nan; % No need to crop the reference frame
%     end
% end
refFrame_cropped = refFrame;
movFrames_cropped = movFrames;
%%
% Outputs
tforms = cell(numel(session_paths), 1);
alignedFrames = cell(numel(session_paths), 1);
Rfixed = imref2d(size(refFrame));
for m = 1:numel(session_paths)
    if m == reference_session_id
        tforms{m} = nan;  
        alignedFrames{m} = nan;  % No alignment needed for the reference session
        continue;
    end
    movFrame = movFrames_cropped{m};
    tforms{m} = imregtform(movFrame, refFrame_cropped, "rigid", optimizer, metric);
    movFrame = movFrames{m};
    alignedFrames{m} = imwarp(movFrame, tforms{m}, "OutputView", Rfixed);
end
% Clear readers when done
clear vid
%%
ref_path = strsplit(session_paths{reference_session_id}, filesep);
ref_path = strjoin(ref_path(1:end-1), filesep);
save(fullfile(ref_path, "registration_results.mat"), "tforms", "Rfixed", "refFrame", "movFrames", "alignedFrames", "-v7.3");
%% check registration quality
f = figure;
tiledlayout(3, numel(session_paths), "Padding", "compact", "TileSpacing", "compact");
for m = 1:numel(session_paths)
    if m == reference_session_id
        continue;  % Skip the reference session
    else
        % movFrame = movFrames_cropped{m};
        movFrame = movFrames{m};
        alignedFrame = alignedFrames{m};
    end

    
    % errBefore = sqrt(mean((double(movFrame) - double(refFrame)).^2, "all"));
    % errAfter = sqrt(mean((double(alignedFrame) - double(refFrame)).^2, "all"));
    % errBefore = corr2(double(movFrame), double(refFrame_cropped));
    % errAfter = corr2(double(alignedFrame(cropRect(2):cropRect(2) + cropRect(4) - 1, cropRect(1):cropRect(1) + cropRect(3) - 1)), double(refFrame_cropped));
    errBefore = corr2(double(movFrame), double(refFrame));
    errAfter = corr2(double(alignedFrame), double(refFrame));

    if errAfter < 0.95
        error('Registeration quality is bad!');
    end
    
    % movFrame = movFrames{m};

    ax1 = nexttile(m);
    imshow(refFrame, []);
    title("Reference");

    ax2 = nexttile(numel(session_paths) + m);
    imshowpair(refFrame, movFrame, "falsecolor");
    % imshowpair(refFrame, movFrame, "diff");
    % clim([0,1]);
    title(sprintf("Before | corr = %.3f", errBefore));

    ax3 = nexttile(2 * numel(session_paths) + m);
    imshowpair(refFrame, alignedFrame, "falsecolor");
    % imshowpair(refFrame, alignedFrame, "diff");
    % clim([0,1]);
    title(sprintf("After | corr = %.3f", errAfter));

    linkaxes([ax1, ax2, ax3]);
end
saveas(f, fullfile(ref_path, "registration_quality_check.png"));
savefig(f, fullfile(ref_path, "registration_quality_check.fig"));

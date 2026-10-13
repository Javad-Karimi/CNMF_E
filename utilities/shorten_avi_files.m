function shorten_avi_files(video_length)
    % input: video_length - number of frames to keep in the shortened video

    profile = 'Grayscale AVI'; % Set the profile for the new video file

    % ask the uder to select an avi file
    [filename, path] = uigetfile('*.AVI', 'Select an AVI file');

    video = VideoReader(fullfile(path, filename));
    
    if ~isfolder(fullfile(path))
        mkdir(fullfile(path));
    end

    v = VideoWriter(fullfile(path, ['shortend_', filename]), profile); % Create new video file
    v.FrameRate = video.FrameRate; 
    open(v)
    % Iterate on all frames in the video and write one frame at a time
    
    frame_counter = 1;
    while frame_counter <= video_length && hasFrame(video) 
        current_frame = readFrame(video); % read each frame
        writeVideo(v,current_frame); % write each frame
        frame_counter = frame_counter + 1;
    end
    
    close(v)
end
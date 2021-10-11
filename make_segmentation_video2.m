function [videoData, fullVideo] = make_segmentation_video2(videoFile, topMaskFile, botMaskFile, t_stats, lickNum, topMaskOrigin, pixPerMillimeter, videoOutputPath, sampleFrameNum)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% make_segmentation_video2: Create a video illustrating the segmentation
%   and trajectory of a mouse tongue licking a spout
% usage:  [videoOutputPath, videoData, fullVideo] 
%               = make_segmentation_video2(videoFile, topMaskFile, 
%                       botMaskFile, t_stats, lickNum, topMaskOrigin, 
%                       pixPerMillimeter, videoOutputPath, sampleFrameNum)
%
% where,
%    videoFile is either a char array representing a path to a mouse tongue
%       video file, or a HxWxN array representing the video data itself.
%    topMaskFile is a char array representing the path to the top mask 
%       stack for the video
%    botMaskFile is a char array representing the path to the bottom mask 
%       stack for the video
%    t_stats is either a char array representing the path to the t_stats
%       file that corresponds to this video or the t_stats struct itself
%    lickNum is a number indicating the lick index from within the t_stats
%       file you wish to select for animation.
%    topMaskOrigin is an optional 1x2 integer vector indicating where, in 
%       video coordinates, to place the upper left corner of the top mask. 
%       For example, [1, 1] would put the top mask right in the upper left 
%       corner of the video. [-20, 50] would put the top mask 21 pixels to 
%       the left, and 49 pixels down. The first element of this is also
%       known as "imshift", and the second element as "y0".
%    pixPerMillimeter is an optional integer indicating the scale of the
%       video in pixels per millimeter, for the purposes of overlaying a
%       scale bar on the video.
%    videoOutputPath is an optional char array representing the path to
%       save the output video to.
%    sampleFrameNum is an optional integer indicating that instead of
%       generating the whole video, to just generate a single sample frame
%       of the video and display it in a figure. This is useful for
%       fine-tuning the parameters, since it is much faster than generating
%       the whole video. sampleFrameNum is the frame number to generate.
%       Omit this parameter or pass in [] to generate whole video instead.
%    videoOutputPath is the path where the output video was saved
%    videoData is the loaded raw video data
%    fullVideo is the data for the final plotted video
%
% This is an update of the original function, make_segmentation_video. 
%   It creates three panes in a horizontal montage. The raw mouse video, 
%   the mouse video with the segmented mask overlay with the tip marked, 
%   and the extracted color-coded trajectory. 
%   
%   This function relies on the new VideoPlotter class, which allows for
%   simple and flexible adding of overlay objects to a video. It is
%   available (at the time of writing) as part of the Goldberg Lab 
%   MATLAB-utils repo. Clone/download that repo, and add it to your MATLAB
%   path before running this function.
%
%   If it's more convenient, a wrapper function,
%   "make_segmentation_video_from_session" calls this function based on a
%   session directory, rather than a specific video.
%   
%   Since loading the video data takes a while, if you are fine-tuning the
%   parameters and running this multiple times, to save time take the
%   "videoData" output and feed it in as the "videoFile" input on the next
%   run. That avoids repeatedly loading the video data from disk, which can
%   save time.
%
% See also: VideoPlotter, make_segmentation_video,
% make_segmentation_video_from_session
%
% Version: 1.0
% Author:  Brian Kardon
% Email:   bmk27=cornell*org, brian*kardon=google*com
% Real_email = regexprep(Email,{'=','*'},{'@','.'})
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

DEFAULT_PIX_PER_MILLIMETER = 20;
DEFAULT_TOP_MASK_ORIGIN = [1, 30];

if ~exist('topMaskOrigin', 'var') || isempty(topMaskOrigin)
    topMaskOrigin = DEFAULT_TOP_MASK_ORIGIN;
end
if ~exist('pixPerMillimeter', 'var') || isempty(pixPerMillimeter)
    pixPerMillimeter = DEFAULT_PIX_PER_MILLIMETER;
end
if ~exist('sampleFrameNum', 'var')
    sampleFrameNum = [];
end
if ~exist('videoOutputPath')
    videoOutputPath = [];
end

%% Load t_stats file
if ischar(t_stats)
    fprintf('Loading t_stats...\n');
    % User passed in char - must be a path. Load t_stats and select lick
    x = load(t_stats);
    t_stats = x.t_stats(lickNum);
elseif length(t_stats) > 1
    % Select a lick from t_stats
    t_stats = t_stats(lickNum);
end

% Find lick start & end frames and length
lickStartFrame = t_stats.pairs(1);
lickEndFrame = t_stats.pairs(2);
lickLength = lickEndFrame - lickStartFrame + 1;

%% Load video
if ischar(videoFile)
    % User passed in a filename, load the video
    fprintf('Loading video...\n');
    videoData = loadVideoData(videoFile);
else
    % User perhaps passed in a raw video data array?
    videoData = videoFile;
    videoFile = '';
end

width = size(videoData, 2);
height = size(videoData, 1);

% For speed, restrict videos to selected lick
videoData = videoData(:, :, lickStartFrame:lickEndFrame);

%% Load masks
fprintf('Loading masks...\n');
topMaskStruct = load(topMaskFile);
botMaskStruct = load(botMaskFile);
topMask = permute(topMaskStruct.mask_pred, [2, 3, 1]);
botMask = permute(botMaskStruct.mask_pred, [2, 3, 1]);

% For speed, restrict videos to selected lick
topMask = topMask(:, :, lickStartFrame:lickEndFrame);
botMask = botMask(:, :, lickStartFrame:lickEndFrame);

% Define location, in video coordinates, of top left corner of the bottom
%   mask (the top mask origin is a function argument)
botMaskOrigin = [1, height - size(botMask, 1)];

%% Define colors
color_protrusion = [0 103 56]/255;
color_CSM = [241 101 33]/255;
color_SSM = [236 177 33]/255;
color_contact = [0, 0, 0]/255;
color_retraction = [101 44 144]/255;
color_mask = [1, 0, 0];
alpha_mask = 0.3;

%% Construct trajectory segment coordinate vectors
% Pack trajectory coordinates into 3xN vector for convenience
tip = [t_stats.tip_x; t_stats.tip_y; t_stats.tip_z];

% Shift trajectory from mask coordinates to video coordinates
tip(1, :) = tip(1, :) + botMaskOrigin(2) - 1;
tip(3, :) = topMaskOrigin(2) + size(topMask, 1) - tip(3, :);

% Create empty trajectories for each trajectory segment
tip_protrusion = nan(size(tip)); 
tip_CSM =        nan(size(tip)); 
tip_SSM =        nan(size(tip)); 
tip_contact =    nan(size(tip)); 
tip_retraction = nan(size(tip));
% Find indices of each segment
idx_protrusion = t_stats.prot_ind:t_stats.CSM_start;
idx_CSM =        t_stats.CSM_start:t_stats.CSM_end;
idx_SSM =        t_stats.SSM_start:t_stats.SSM_end;
idx_contact =    t_stats.SSM_start;
idx_retraction = t_stats.ret_ind:size(tip, 2);
% Cut and paste each coordinates for each trajectory segment
tip_protrusion(:, idx_protrusion) = tip(:, idx_protrusion);
tip_CSM(:, idx_CSM) =               tip(:, idx_CSM);
tip_SSM(:, idx_SSM) =               tip(:, idx_SSM);
tip_contact(:, idx_contact) =       tip(:, idx_contact);
tip_retraction(:, idx_retraction) = tip(:, idx_retraction);

%% Lay out video plots
% Create plotter object
fprintf('Creating VideoPlotter objects...\n');
rawPlot =    VideoPlotter(videoData);
maskedPlot = VideoPlotter(videoData);
graphPlot =  VideoPlotter(ones(size(videoData)));

fprintf('Adding mask overlays...\n');
% Add top and bottom overlay to masked plot
maskedPlot.addOverlay(topMask, color_mask, alpha_mask, topMaskOrigin);
maskedPlot.addOverlay(botMask, color_mask, alpha_mask, botMaskOrigin);
% Add tip location to masked plot
maskedPlot.addPlot(tip(2, :), tip(1, :), 0, 'Marker', 'o', 'MarkerEdgeColor', 'yellow', 'LineWidth', 2);
maskedPlot.addPlot(tip(2, :), tip(3, :), 0, 'Marker', 'o', 'MarkerEdgeColor', 'yellow', 'LineWidth', 2);

% Add frame number to raw plot
frameNumberText = arrayfun(@(t)sprintf('%03d ms', t), 1:lickLength, 'UniformOutput', false);
rawPlot.addText(frameNumberText, 20, height - 20, 'Color', 'white');

% Add trajectories to graph plot
graphPlot.addPlot(tip_protrusion(2, :), tip_protrusion(3, :), 1, 'Color', color_protrusion, 'Marker', 'none');
graphPlot.addPlot(tip_protrusion(2, :), tip_protrusion(1, :), 1, 'Color', color_protrusion, 'Marker', 'none');
graphPlot.addPlot(tip_protrusion(2, :), tip_protrusion(3, :), 0, 'Color', color_protrusion, 'Marker', 'o');
graphPlot.addPlot(tip_protrusion(2, :), tip_protrusion(1, :), 0, 'Color', color_protrusion, 'Marker', 'o');
graphPlot.addPlot(tip_CSM(2, :),        tip_CSM(3, :),        1, 'Color', color_CSM, 'Marker', 'none');
graphPlot.addPlot(tip_CSM(2, :),        tip_CSM(1, :),        1, 'Color', color_CSM, 'Marker', 'none');
graphPlot.addPlot(tip_CSM(2, :),        tip_CSM(3, :),        0, 'Color', color_CSM, 'Marker', 'o');
graphPlot.addPlot(tip_CSM(2, :),        tip_CSM(1, :),        0, 'Color', color_CSM, 'Marker', 'o');
graphPlot.addPlot(tip_SSM(2, :),        tip_SSM(3, :),        1, 'Color', color_SSM, 'Marker', 'none');
graphPlot.addPlot(tip_SSM(2, :),        tip_SSM(1, :),        1, 'Color', color_SSM, 'Marker', 'none');
graphPlot.addPlot(tip_SSM(2, :),        tip_SSM(3, :),        0, 'Color', color_SSM, 'Marker', 'o');
graphPlot.addPlot(tip_SSM(2, :),        tip_SSM(1, :),        0, 'Color', color_SSM, 'Marker', 'o');
graphPlot.addPlot(tip_contact(2, :),    tip_contact(3, :),    1, 'Color', color_contact, 'Marker', 'x', 'LineWidth', 1.5, 'MarkerSize', 7);
graphPlot.addPlot(tip_contact(2, :),    tip_contact(1, :),    1, 'Color', color_contact, 'Marker', 'x', 'LineWidth', 1.5, 'MarkerSize', 7);
graphPlot.addPlot(tip_retraction(2, :), tip_retraction(3, :), 1, 'Color', color_retraction, 'Marker', 'none');
graphPlot.addPlot(tip_retraction(2, :), tip_retraction(1, :), 1, 'Color', color_retraction, 'Marker', 'none');
graphPlot.addPlot(tip_retraction(2, :), tip_retraction(3, :), 0, 'Color', color_retraction, 'Marker', 'o');
graphPlot.addPlot(tip_retraction(2, :), tip_retraction(1, :), 0, 'Color', color_retraction, 'Marker', 'o');

% Add scale bar
graphPlot.addText('1 mm', width-50, height-30, 'Color', 'black');
graphPlot.addPlot([width-50, width-50+pixPerMillimeter], ...
                  [height-20, height-20], NaN, 'Color', 'black', 'LineWidth', 2);


%% Generate videos or sample frame
if isempty(sampleFrameNum)
    % Generate whole video, not just a sample frame
    fprintf('Generating the raw video...\n');
    rawVideo = rawPlot.getVideoPlot();
    fprintf('Generating the masked video...\n');
    maskedVideo = maskedPlot.getVideoPlot();
    fprintf('Generating the trajectory video...\n');
    graphVideo = graphPlot.getVideoPlot();
    fprintf('Done generating videos.\n');
else
    fprintf('Generating sample frame...\n');
    rawVideo = rawPlot.getFrame(sampleFrameNum);
    maskedVideo = maskedPlot.getFrame(sampleFrameNum);
    graphVideo = graphPlot.getFrame(sampleFrameNum);
end

% Set the videos side by side
fullVideo = horzcat(rawVideo, maskedVideo, graphVideo);

%% Save video to file
if isempty(sampleFrameNum)
    [path, name, ext] = fileparts(videoFile);
    if isempty(videoOutputPath)
        videoOutputPath = fullfile(path, [name, '_trajectory', ext]);
    end
    fprintf('Saving the full video to %s\n', videoOutputPath);
    saveVideoData(fullVideo, videoOutputPath);
else
    fprintf('Displaying sample frame...\n');
    figure; imshow(fullVideo);
end
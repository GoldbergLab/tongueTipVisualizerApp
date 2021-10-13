function [videoData, fullVideo] = make_segmentation_video2(videoPath, topMaskPath, botMaskPath, t_stats, topMaskOrigin, pixPerMillimeter, framePadding, videoOutputPath, sampleFrameNum, ffmpegCompress)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% make_segmentation_video2: Create a video illustrating the segmentation
%   and trajectory of a mouse tongue licking a spout
% usage:  [videoOutputPath, videoData, fullVideo] 
%               = make_segmentation_video2(videoPath, topMaskPath, 
%                       botMaskPath, t_stats, lickNum, topMaskOrigin, 
%                       pixPerMillimeter, videoOutputPath, sampleFrameNum, 
%                       ffmpegCompress)
%
% where,
%    videoPath is either a char array representing a path to a mouse tongue
%       video file, or a HxWxN array representing the video data itself.
%    topMaskPath is a char array representing the path to the top mask 
%       stack for the video
%    botMaskPath is a char array representing the path to the bottom mask 
%       stack for the video
%    t_stats is a t_stats struct subset that contains all the licks you
%       wish to plot. Note that this is designed to only plot within a
%       single bout - supplying a t_stats file that is not consecutive or
%       crosses bouts will result in an error.
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
%    ffmpegCompress is an option boolean flag that indicates whether or not
%       to attempt to recompress the output video using ffmpeg. This will 
%       only work if ffmpeg is installed and available on your system PATH.
%       Lossless compression is used, so there is no quality loss, but
%       typically you get a 10x compression ratio because MATLAB does not 
%       save compressed video. Default is false.
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
%   "videoData" output and feed it in as the "videoPath" input on the next
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

%% Handle default arguments
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
if ~exist('videoOutputPath', 'var')
    videoOutputPath = [];
end
if ~exist('framePadding', 'var') || isempty(framePadding)
    framePadding = [0, 0];
elseif length(framePadding) == 1
    framePadding = [framePadding, framePadding];
end
if ~exist('ffmpegCompress', 'var') || isempty(ffmpegCompress)
    ffmpegCompress = false;
end

%% Define colors
dimFactor = 0.65;  % Number from 0 to 1, where 0 leaves color unchanged, and 1 makes color white
color_protrusion = [0 103 56]/255;
color_protrusion_dim = dimColor(color_protrusion, dimFactor);
color_CSM = [241 101 33]/255;
color_CSM_dim = dimColor(color_CSM, dimFactor);
color_SSM = [236 177 33]/255;
color_SSM_dim = dimColor(color_SSM, dimFactor);
color_contact = [0, 0, 0]/255;
color_contact_dim = dimColor(color_contact, dimFactor);
color_retraction = [101 44 144]/255;
color_retraction_dim = dimColor(color_retraction, dimFactor);
color_mask = [1, 0, 0];
alpha_mask = 0.3;

%% Load t_stats file
switch class(t_stats)
    case 'char'
        error('A char array was passed in for t_stats where a struct was expected. Please load the t_stats struct, select the licks you want, and pass the struct in directly.');
    case 'struct'
        if any(diff([t_stats.lick_index]) ~= 1)
            error('Lick indices in the supplied t_stats structure are not consecutive. This is not currently supported.');
        end
        if length(unique([t_stats.trial_num])) > 1
            error('t_stats file contains parts of more than one bout. Please filter the t_stats struct to contain only one bout, or a subset of a bout.');
        end
    otherwise
        error('t_stats must be a struct.');
end

%% Calculate clip start and end frames based on t_stats
if length(t_stats) > 1 && t_stats(1).lick_index == 1
    % This is a bout starting on lick_index 1 - start with the cue
    clipStartFrame = max(1, t_stats(1).pairs(1) - t_stats(1).time_rel_cue - framePadding(1));
else
    % Either a single lick or a lick chain that starts in the middle of a bout. 
    % Just start on the first lick onset
    clipStartFrame = max(t_stats(1).pairs(1) - framePadding(1));
end
clipEndFrame = t_stats(end).pairs(2) + framePadding(2);
clipLength = clipEndFrame - clipStartFrame + 1;

%% Load video
if ischar(videoPath)
    % User passed in a filename, load the video
    fprintf('Loading video...\n');
    videoData = loadVideoData(videoPath);
else
    % User perhaps passed in a raw video data array?
    videoData = videoPath;
    videoPath = 'UnnamedVideo.avi';
end

width = size(videoData, 2);
height = size(videoData, 1);

% For speed, restrict videos to selected lick
videoData = videoData(:, :, clipStartFrame:clipEndFrame);

%% Load masks
fprintf('Loading masks...\n');
topMaskStruct = load(topMaskPath);
botMaskStruct = load(botMaskPath);
topMask = permute(topMaskStruct.mask_pred, [2, 3, 1]);
botMask = permute(botMaskStruct.mask_pred, [2, 3, 1]);

% For speed, restrict videos to selected lick
topMask = topMask(:, :, clipStartFrame:clipEndFrame);
botMask = botMask(:, :, clipStartFrame:clipEndFrame);

% Define location, in video coordinates, of top left corner of the bottom
%   mask (the top mask origin is a function argument)
botMaskOrigin = [1, height - size(botMask, 1)];

%% Create plotter objects
fprintf('Creating VideoPlotter objects...\n');
rawPlot =    VideoPlotter(videoData);
maskedPlot = VideoPlotter(videoData);
graphPlot =  VideoPlotter(ones(size(videoData)));

%% Add mask overlays
fprintf('Adding mask overlays...\n');
% Add top and bottom overlay to masked plot
maskedPlot.addOverlay(topMask, color_mask, alpha_mask, topMaskOrigin);
maskedPlot.addOverlay(botMask, color_mask, alpha_mask, botMaskOrigin);

%% Add lick-specific overlays
for k = 1:length(t_stats)
    % Loop over each lick in t_stats, adding graphics overlays
    fprintf('Adding overlays for lick #%d of %d\n', k, length(t_stats));
    lickStartFrame = t_stats(k).pairs(1) - clipStartFrame + 1;
    lickEndFrame =   t_stats(k).pairs(2) - clipStartFrame + 1;
    
    % Pack trajectory coordinates into 3xN vector for convenience
    tip = [t_stats(k).tip_x; t_stats(k).tip_y; t_stats(k).tip_z];

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
    idx_protrusion = 1:t_stats(k).prot_ind;  % Note, prot_ind and CSM_start should (always?) be the same.
    idx_CSM =        t_stats(k).CSM_start:t_stats(k).CSM_end;
    idx_SSM =        t_stats(k).SSM_start:t_stats(k).SSM_end;
    idx_contact =    t_stats(k).SSM_start;
    idx_retraction = t_stats(k).ret_ind:size(tip, 2);
    % Cut and paste each coordinates for each trajectory segment
    tip_protrusion(:, idx_protrusion) = tip(:, idx_protrusion);
    tip_CSM(:, idx_CSM) =               tip(:, idx_CSM);
    tip_SSM(:, idx_SSM) =               tip(:, idx_SSM);
    tip_contact(:, idx_contact) =       tip(:, idx_contact);
    tip_retraction(:, idx_retraction) = tip(:, idx_retraction);

    % Prepare "spout contact" flash text
    contactTxts = repmat({''}, [1, 10]);
    flashStartFrame = idx_contact + lickStartFrame - 1;
    if flashStartFrame + 10 > clipEndFrame
        warning('Spout contact flash text will get cut off by the end of the video, and won''t fully display');
    end
    txtX = tip(2, idx_contact) - 30;
    txtY = tip(3, idx_contact) + 20;

    %% Lay out video plots
    % Add tip location to masked plot
    maskedPlot.addPlot(tip(2, :), tip(1, :), lickStartFrame, 0, 'Marker', 'o', 'MarkerEdgeColor', 'yellow', 'LineWidth', 2);
    maskedPlot.addPlot(tip(2, :), tip(3, :), lickStartFrame, 0, 'Marker', 'o', 'MarkerEdgeColor', 'yellow', 'LineWidth', 2);

    % Add trajectories to graph plot
    graphPlot.addPlot(tip_protrusion(2, :), tip_protrusion(3, :), lickStartFrame, 1,   'Color', color_protrusion,     'Marker', 'none');
    graphPlot.addPlot(tip_protrusion(2, :), tip_protrusion(1, :), lickStartFrame, 1,   'Color', color_protrusion,     'Marker', 'none');
    graphPlot.addPlot(tip_CSM(2, :),        tip_CSM(3, :),        lickStartFrame, 1,   'Color', color_CSM,            'Marker', 'none');
    graphPlot.addPlot(tip_CSM(2, :),        tip_CSM(1, :),        lickStartFrame, 1,   'Color', color_CSM,            'Marker', 'none');
    graphPlot.addPlot(tip_SSM(2, :),        tip_SSM(3, :),        lickStartFrame, 1,   'Color', color_SSM,            'Marker', 'none');
    graphPlot.addPlot(tip_SSM(2, :),        tip_SSM(1, :),        lickStartFrame, 1,   'Color', color_SSM,            'Marker', 'none');
    graphPlot.addPlot(tip_retraction(2, :), tip_retraction(3, :), lickStartFrame, 1,   'Color', color_retraction,     'Marker', 'none');
    graphPlot.addPlot(tip_retraction(2, :), tip_retraction(1, :), lickStartFrame, 1,   'Color', color_retraction,     'Marker', 'none');

    % Add trajectory tips to graph plot
    graphPlot.addPlot(tip_protrusion(2, :), tip_protrusion(3, :), lickStartFrame, 0,   'Color', color_protrusion,     'Marker', 'o');
    graphPlot.addPlot(tip_protrusion(2, :), tip_protrusion(1, :), lickStartFrame, 0,   'Color', color_protrusion,     'Marker', 'o');
    graphPlot.addPlot(tip_CSM(2, :),        tip_CSM(3, :),        lickStartFrame, 0,   'Color', color_CSM,            'Marker', 'o');
    graphPlot.addPlot(tip_CSM(2, :),        tip_CSM(1, :),        lickStartFrame, 0,   'Color', color_CSM,            'Marker', 'o');
    graphPlot.addPlot(tip_SSM(2, :),        tip_SSM(3, :),        lickStartFrame, 0,   'Color', color_SSM,            'Marker', 'o');
    graphPlot.addPlot(tip_SSM(2, :),        tip_SSM(1, :),        lickStartFrame, 0,   'Color', color_SSM,            'Marker', 'o');
    graphPlot.addPlot(tip_retraction(2, :), tip_retraction(3, :), lickStartFrame, 0,   'Color', color_retraction,     'Marker', 'o');
    graphPlot.addPlot(tip_retraction(2, :), tip_retraction(1, :), lickStartFrame, 0,   'Color', color_retraction,     'Marker', 'o');
    
    if k < length(t_stats)
        % Add ghosts of trajectories past (unless this is the last lick)
        graphPlot.addStaticPlot(tip_protrusion(2, :), tip_protrusion(3, :), lickEndFrame+1, nan, 'Color', color_protrusion_dim, 'Marker', 'none');
        graphPlot.addStaticPlot(tip_protrusion(2, :), tip_protrusion(1, :), lickEndFrame+1, nan, 'Color', color_protrusion_dim, 'Marker', 'none');
        graphPlot.addStaticPlot(tip_CSM(2, :),        tip_CSM(3, :),        lickEndFrame+1, nan, 'Color', color_CSM_dim,        'Marker', 'none');
        graphPlot.addStaticPlot(tip_CSM(2, :),        tip_CSM(1, :),        lickEndFrame+1, nan, 'Color', color_CSM_dim,        'Marker', 'none');
        graphPlot.addStaticPlot(tip_SSM(2, :),        tip_SSM(3, :),        lickEndFrame+1, nan, 'Color', color_SSM_dim,        'Marker', 'none');
        graphPlot.addStaticPlot(tip_SSM(2, :),        tip_SSM(1, :),        lickEndFrame+1, nan, 'Color', color_SSM_dim,        'Marker', 'none');
        graphPlot.addStaticPlot(tip_contact(2, :),    tip_contact(3, :),    lickEndFrame+1, nan, 'Color', color_contact_dim,    'Marker', 'x', 'LineWidth', 1.5, 'MarkerSize', 7);
        graphPlot.addStaticPlot(tip_contact(2, :),    tip_contact(1, :),    lickEndFrame+1, nan, 'Color', color_contact_dim,    'Marker', 'x', 'LineWidth', 1.5, 'MarkerSize', 7);
        graphPlot.addStaticPlot(tip_retraction(2, :), tip_retraction(3, :), lickEndFrame+1, nan, 'Color', color_retraction_dim, 'Marker', 'none');
        graphPlot.addStaticPlot(tip_retraction(2, :), tip_retraction(1, :), lickEndFrame+1, nan, 'Color', color_retraction_dim, 'Marker', 'none');
    end

    % Add "spout contact" X and flash text
    graphPlot.addPlot(tip_contact(2, :),    tip_contact(3, :),    lickStartFrame, 1,   'Color', color_contact,        'Marker', 'x', 'LineWidth', 1.5, 'MarkerSize', 7);
    graphPlot.addPlot(tip_contact(2, :),    tip_contact(1, :),    lickStartFrame, 1,   'Color', color_contact,        'Marker', 'x', 'LineWidth', 1.5, 'MarkerSize', 7);
    graphPlot.addText(contactTxts, txtX, txtY, flashStartFrame, 'FontSize', 8);

end

%% Add general overlays
% Prepare frame number text
frameNumberText = arrayfun(@(t)sprintf('%03d ms', t), 1:clipLength, 'UniformOutput', false);

% Add frame number to raw plot
rawPlot.addText(frameNumberText, 20, height - 20, 1, 'Color', 'white');

% Add scale bar
graphPlot.addText('1 mm', width-50, height-30, 1, 'Color', 'black');
postPad = nan([1, clipLength - 2]);
graphPlot.addPlot([width-50, width-50+pixPerMillimeter, postPad], ...
                  [height-20, height-20, postPad], 1, NaN, 'Color', 'black', 'LineWidth', 2);

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
    if isempty(videoOutputPath)
        [path, name, ext] = fileparts(videoPath);
        videoOutputPath = fullfile(path, [name, '_trajectory', ext]);
    end
    fprintf('Saving the full video to %s\n', videoOutputPath);
    saveVideoData(fullVideo, videoOutputPath);
else
    fprintf('Displaying sample frame...\n');
    figure; imshow(fullVideo);
end

%% Compressing video
if ffmpegCompress
    fprintf('Compressing video using ffmpeg...');
    [path, ~, ~] = fileparts(videoOutputPath);
    tempPath = getNextAvailablePath(fullfile(path, 'temp_msv.avi'));
    [status, cmdout] = system(sprintf('ffmpeg -i "%s" -c:v libx264 -crf 0 "%s"', videoOutputPath, tempPath));
    disp(cmdout);
    if status ~= 0
        error('Error compressing output video with ffmpeg.')
    end
    movefile(tempPath, videoOutputPath);
end

function dimRGB = dimColor(rgb, dimFactor, dimToColor)
% rgb = a color vector with elements between 0 and 1
% dimFactor a number between 0 and 1 indicating how much to dim
% dimToColor is an optional rgb color to dim to. Default: white ([1, 1, 1])
if ~exist('dimToColor', 'var') || isempty(dimToColor)
    dimToColor = [1, 1, 1];
end
dimRGB = (rgb * (1 - dimFactor) + dimToColor * dimFactor);
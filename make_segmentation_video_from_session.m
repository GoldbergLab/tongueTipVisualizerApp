function make_segmentation_video_from_session(videoDir, maskDir, outputDir, trialNum, lickIndices, topMaskOrigin, pixPerMillimeter, framePadding, sampleFrameNum, ffmpegCompress)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% make_segmentation_video_from_session: Create a video illustrating the 
%   segmentation and trajectory of a mouse tongue licking a spout based on
%   session directories and trial/lick indices.
% usage: make_segmentation_video_from_session(videoDir, 
%           maskDir, outputDir, trialNum, lickIndices, topMaskOrigin, 
%           pixPerMillimeter, framePadding, sampleFrameNum, ffmpegCompress)
%
% where,
%    videoDir is a char array representing a path to a folder containing
%       video files for a lick session
%    maskDir is a char array representing the path to a folder containing
%       the top and bottom segmented masks corresponding to the videos in
%       videoDir. It should also contain a t_stats struct file named
%       't_stats.mat'.
%    outputDir is a char array representing the path to a folder to save
%       the output video to.
%    trialNum is an integer representing which trial number to include in
%       the video.
%    lickIndices is a number or array of numbers indicating the lick index
%       or indices to include in the video, where 1 indicates the first
%       lick in the bout. If more than one are provided, they must be
%       consecutive (for example, [1, 2, 3, 4]). Pass an empty array to
%       select all licks in the specified trial.
%    topMaskOrigin is an optional 1x2 integer vector indicating where, in 
%       video coordinates, to place the upper left corner of the top mask. 
%       For example, [1, 1] would put the top mask right in the upper left 
%       corner of the video. [-20, 50] would put the top mask 21 pixels to 
%       the left, and 49 pixels down. The first element of this is also
%       known as "imshift", and the second element as "y0".
%    pixPerMillimeter is an optional integer indicating the scale of the
%       video in pixels per millimeter, for the purposes of overlaying a
%       scale bar on the video.
%    framePadding is an optional integer or pair of integers indicating the
%       how many extra frames to add to the beginning and/or end of the 
%       video. A single integer will pad both ends of the video equally.
%       Supplying an array of two integers will result in the start of the
%       video padded by framePadding(1) and the end padded by
%       framePadding(2). Omitting or passing an empty array will result in
%       no padding.
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
%
% This is a wrapper for the function make_segmentation_video2 that makes it
%   possible to run that function without having to find specific file 
%   paths, instead specifying directories and trial/lick indices. 
%   See the documentation of that function for more details.
%
% See also: make_segmentation_video2, VideoPlotter
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
if ~exist('framePadding', 'var')
    framePadding = [];
end
if ~exist('ffmpegCompress', 'var') || isempty(ffmpegCompress)
    ffmpegCompress = false;
end

%% Get video path
videoList = findFilesByRegex(videoDir, '.*\.avi');
if trialNum > length(videoList)
    error('Requested trial number %d, but there are only %d videos in the provided directory.', trialNum, length(videoList));
end
videoPath = videoList{trialNum};

%% Load and filter t_stats
x = load(fullfile(maskDir,'t_stats.mat'), 't_stats');
t_stats = x.t_stats;
% Filter by trial number
t_stats = t_stats([t_stats.trial_num] == trialNum);
if ~isempty(lickIndices)
    % Filter by lick indices
    t_stats = t_stats(vecEq([t_stats.lick_index], lickIndices));
else
    % No lick indices provided - use all licks in this trial.
    lickIndices = [t_stats.lick_index];
end

%% Construct an output video path
[~, name, ~] = fileparts(videoPath);
outputName = sprintf('%s_T%d_L%d-%d.avi', name, trialNum, min(lickIndices), max(lickIndices));
videoOutputPath = fullfile(outputDir, outputName);

%% Get corresponding mask file paths
botMaskPath = fullfile(maskDir, sprintf('Bot_%03d.mat', trialNum-1));
topMaskPath = fullfile(maskDir, sprintf('Top_%03d.mat', trialNum-1));
if ~exist(botMaskPath, 'file')
    error('Bottom mask file not found: %s\n', botMaskPath);
end
if ~exist(topMaskPath, 'file')
    error('Top mask file not found: %s\n', topMaskPath);
end

%% Create video
make_segmentation_video2(videoPath, topMaskPath, botMaskPath, t_stats, ...
    topMaskOrigin, pixPerMillimeter, framePadding, videoOutputPath, ...
    sampleFrameNum, ffmpegCompress);

function e = vecEq(vec, values)
if iscolumn(vec)
    vec = vec';
end
if isrow(values)
    values = values';
end
e = any(vec == values, 1);


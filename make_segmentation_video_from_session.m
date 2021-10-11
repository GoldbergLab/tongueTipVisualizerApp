function [videoOutputPath, videoData, fullVideo] = make_segmentation_video_from_session(videoDir,maskDir,destDir,trial_num_list,filler_lines,im_shift,input_index, lickNum, topMaskOrigin, pixPerMillimeter, sampleFrameNum)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% make_segmentation_video_from_session: Create a video illustrating the 
%   segmentation and trajectory of a mouse tongue licking a spout
% usage:  [videoOutputPath, videoData, fullVideo] 
%               = make_segmentation_video_from_session(videoFile, topMaskFile, 
%                       botMaskFile, t_stats, lickNum, topMaskOrigin, 
%                       pixPerMillimeter)
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
%   Since loading the video data takes a while, if you are fine-tuning the
%   parameters and running this multiple times, to save time take the
%   "videoData" output and feed it in as the "videoFile" input on the next
%   run. That avoids repeatedly loading the video data from disk, which can
%   save time.
%
% See also: VideoPlotter, make_segmentation_video
%
% Version: 1.0
% Author:  Brian Kardon
% Email:   bmk27=cornell*org, brian*kardon=google*com
% Real_email = regexprep(Email,{'=','*'},{'@','.'})
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% Get list of videos
videoList = findFilesByRegex(videoDir, '.*\.avi');

% Load t_stats
load(fullfile(maskDir,'t_stats.mat'), 't_stats');
%load(strcat(segmentation_dir.name,'/tip_track.mat'));
lickIndex = find([t_stats.lick_index]==input_index);
l_stats = t_stats(lickIndex);

prot_color = [0 103 56]/255;
csm_color = [241 101 33]/255;
ssm_color = [236 177 33]/255;
ret_color = [101 44 144]/255;

dirlist_bot = rdir(strcat(segmentation_dir.name,'\Bot*'));
dirlist_top = rdir(strcat(segmentation_dir.name,'\Top*'));

d = fdesign.lowpass('N,F3db',3, 50, 1000);
hd = design(d, 'butter');

for i = 1:numel(l_stats)
        try
        trial_ind = l_stats(i).trial_num;
        if ~sum(ismember(trial_ind,trial_num_list))>0
            continue
        end
        display(dirlist_video(trial_ind).name);
        %load estimated tip
        tip_x = l_stats(i).tip_x;
        tip_y = l_stats(i).tip_y;
        tip_z = l_stats(i).tip_z;  
%         tip_x = l_stats(i).tip_x_raw;
%         tip_y = l_stats(i).tip_y_raw;
%         tip_z = l_stats(i).tip_z_raw;                
%         
%         tip_x = filter_and_scale(tip_x(3:end-1),hd);
%         tip_y = filter_and_scale(tip_y(3:end-1),hd);
%         tip_z = filter_and_scale(tip_z(3:end-1),hd);
        
        %load and reshape video
        v = VideoReader(dirlist_video(trial_ind).name);

         [videoData, fullVideo] = make_segmentation_video2(videoFile, topMaskFile, botMaskFile, t_stats, lickNum, topMaskOrigin, pixPerMillimeter, videoOutputPath, sampleFrameNum)

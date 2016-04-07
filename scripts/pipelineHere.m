

% New pipeline script. 
% As before, first set options variable "ops". 

addpath(genpath('/mnt/zserver/Code/Rigging'));
addpath(genpath('/mnt/data/svdinput/npy-matlab'));
addpath('/mnt/data/svdinput/'); % for +dat

load ops.mat; % this must be present in the current directory
diaryFilename = sprintf('svdLog_%s_%s.txt', ops.mouseName, ops.thisDate);
diary(diaryFilename);

ops.localSavePath = pathForThisOS(ops.localSavePath);
for v = 1:length(ops.vids)
    ops.vids(v).fileBase = pathForThisOS(ops.vids(v).fileBase);
end

if ~exist(ops.localSavePath, 'dir')
    mkdir(ops.localSavePath);
end
save(fullfile(ops.localSavePath, 'ops.mat'), 'ops');

%% load all movies into flat binary files

for v = 1:length(ops.vids)
    
    clear loadDatOps;
    
    ops.theseFiles = [];
    theseFiles = generateFileList(ops, v);
    
    ops.vids(v).theseFiles = theseFiles;
    loadDatOps.theseFiles = theseFiles;
        
    ops.vids(v).thisDatPath = fullfile(ops.localSavePath, ['vid' num2str(v) 'raw.dat']);
    loadDatOps.datPath = ops.vids(v).thisDatPath;    
    loadDatOps.verbose = ops.verbose;
    
    loadDatOps.frameMod = ops.vids(v).frameMod;
    loadDatOps.hasASCIIstamp = ops.hasASCIIstamp;
    loadDatOps.hasBinaryStamp = ops.hasBinaryStamp;
    loadDatOps.binning = ops.binning;
    
    dataSummary = loadRawToDat(loadDatOps);
    
    fn = fieldnames(dataSummary);
    results(v).name = ops.vids(v).name;
    for f = 1:length(fn)
        results(v).(fn{f}) = dataSummary.(fn{f});
    end
    
    save(fullfile(ops.localSavePath, 'results.mat'), 'results');
end

%% do image registration? 
% Register the blue image and apply the registration to the other movies
if ops.doRegistration
    % if you want to do registration, we need to first determine the
    % target image.
    tic
    if ops.verbose
        fprintf(1, 'determining target image\n');
    end
    [targetFrame, nFr] = generateRegistrationTarget(ops.fileBase, ops);
    ops.Nframes = nFr;
    toc
else
    targetFrame = [];
end

%% do hemodynamic correction?
% - don't do this here - it likely works just as well on SVD representation
% (though that has not been explicitly tested). 


%% perform SVD
for v = 1:length(ops.vids)
    fprintf(1, ['svd on ' ops.vids(v).name '\n']);
    
    svdOps.Ly = results(v).imageSize(1); svdOps.Lx = results(v).imageSize(2); % not actually used in SVD function, just locally here

    if ops.doRegistration
        minDs = min(dataSummary.regDs, [], 1);
        maxDs = max(dataSummary.regDs, [], 1);

        svdOps.yrange = ceil(maxDs(1)):floor(svdOps.Ly+minDs(1));
        svdOps.xrange = ceil(maxDs(2)):floor(svdOps.Lx+minDs(2));    
        
        svdOps.RegFile = ops.vids(v).thisRegPath;
    else
        svdOps.yrange = 1:svdOps.Ly; % subselection/ROI of image to use
        svdOps.xrange = 1:svdOps.Lx;
        svdOps.RegFile = ops.vids(v).thisDatPath;
    end
    svdOps.Nframes = numel(results(v).timeStamps); % number of frames in whole movie

    svdOps.mimg = results(v).meanImage;

    svdOps.ResultsSaveFilename = [];
    svdOps.theseFiles = ops.vids(v).theseFiles;    
    
    tic
    [ops, U, Sv, V, totalVar] = get_svdcomps(svdOps);
    toc   
    
    % what to do about this? Need to save all "vids" - where?
    fprintf(1, 'attempting to save to server\n')
    ops.thisVid = v;
    ops.rigName = ops.vids(v).rigName;
    results.vids(v).Sv = Sv;
    results.vids(v).totalVar = totalVar;
    saveSVD(ops, U, V, results.vids(v))
    
    results.vids(v).U = U;
    results.vids(v).V = V;
    
    
end

%% save

fprintf(1, 'saving all locally\n');
save(fullfile(ops.localSavePath, 'results.mat'), 'results', '-v7.3');



fprintf(1, 'done\n');
diary off;

if isfield(ops, 'emailAddress') && ~isempty(ops.emailAddress)
    mail = 'lugaro.svd@gmail.com'; %Your GMail email address
    password = 'xpr!mnt1'; %Your GMail password
    
    % Then this code will set up the preferences properly:
    setpref('Internet','E_mail',mail);
    setpref('Internet','SMTP_Server','smtp.gmail.com');
    setpref('Internet','SMTP_Username',mail);
    setpref('Internet','SMTP_Password',password);
    props = java.lang.System.getProperties;
    props.setProperty('mail.smtp.auth','true');
    props.setProperty('mail.smtp.socketFactory.class', 'javax.net.ssl.SSLSocketFactory');
    props.setProperty('mail.smtp.socketFactory.port','465');    
                                                                                                                                                                         messages = {'I am the SVD master.', 'But I can''t help the fact that your data sucks.', 'Decomposing all day, decomposing all night.', 'You''re welcome.', 'Now you owe me a beer.'};    
    % Send the email
    sendmail(ops.emailAddress,[ops.mouseName '_' ops.thisDate ' finished.'], ...
        messages{randi(numel(messages),1)}, diaryFilename);

end

% save(fullfile(ops.localSavePath, 'done.mat'), []);
% Instead, copy the folder of raw files into the /mnt/data/toArchive folder
destFolder = fullfile('/mnt/data/toarchive/', ops.mouseName, ops.thisDate);
mkdir(destFolder);
movefile(fullfile('/mnt/data/svdinput/', ops.mouseName, ops.thisDate, '*'), destFolder);
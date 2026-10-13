function runDeconvolution()
    numcores = feature('numcores'); 

    % Create a "local" cluster object
    local_cluster = parcluster('local');

    % Modify the JobStorageLocation to $SLURM_TMPDIR
    local_cluster.JobStorageLocation = getenv('SLURM_TMPDIR');

    % Start the parallel pool
    parpool(local_cluster,numcores);

    analysis_path = pwd; %put in path to folder in question here (or make copy of this file within the folder you want to run and enjoy)

    addpath(genpath('/home/abadchi/links/CNMF_E/'));
    addpath(genpath('/home/abadchi/links/NoRMCorre/'));

    % oldcd = analysis_path;
    % cvx_setup;

    cd(analysis_path);
    
    run_deconvolution(analysis_path);
end
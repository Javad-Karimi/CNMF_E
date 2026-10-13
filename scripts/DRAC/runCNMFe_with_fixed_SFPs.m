function runCNMFe_with_fixed_SFPs()
    numcores = feature('numcores'); 

    % Create a "local" cluster object
    local_cluster = parcluster('local');

    % Modify the JobStorageLocation to $SLURM_TMPDIR
    local_cluster.JobStorageLocation = getenv('SLURM_TMPDIR');

    % Start the parallel pool
    parpool(local_cluster,numcores);
 
    %put in path to folder in question here (or make copy of this file within the folder you want to run and enjoy)
    analysis_path = pwd;
    
    addpath(genpath('/home/abadchi/links/CNMF_E/'));
    addpath(genpath('/home/abadchi/links/NoRMCorre/'));
    
    % oldcd = analysis_path;

    % cd('/home/abadchi/links/CNMF_E/');
    % cvx_setup;

    cd(analysis_path);
    
    run_CNMFE_with_fixed_SFPs(analysis_path);
end
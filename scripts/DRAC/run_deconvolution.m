function run_deconvolution(session_path)
cd(session_path);
load('ms_union.mat', 'FiltTraces');
baseline_percentile_win = 32; % in seconds
camera_srate = 30; % frames per second
baseline_percentile = 10; 
%decay_tau = 0.7, rise_tau = 0.2333
taus = [0.7, 0.2333]; %[decay, rise] time constants in seconds
taus = taus*camera_srate;

baseline = zeros(size(FiltTraces));

parfor frame_counter = 1:size(FiltTraces,1)
    if frame_counter - round(baseline_percentile_win*camera_srate) > 0
        baseline(frame_counter,:) = ...
            prctile(FiltTraces(frame_counter + (-round(baseline_percentile_win*camera_srate):0),:),baseline_percentile,1);
    else
        baseline(frame_counter,:) = prctile(FiltTraces(1:frame_counter,:),baseline_percentile,1);
    end
end
cal_traces_detrended = FiltTraces - baseline;

denoisedCa_lambda_0 = zeros(size(FiltTraces));
denoisedCa_lambda_0p2 = zeros(size(FiltTraces));
denoisedCa_lambda_0p4 = zeros(size(FiltTraces));
deconvolvedCa_lambda_0 = zeros(size(FiltTraces));
deconvolvedCa_lambda_0p2 = zeros(size(FiltTraces));
deconvolvedCa_lambda_0p4 = zeros(size(FiltTraces));

parfor trace_counter = 1 : size(FiltTraces,2)
    [denoisedCa_lambda_0(:,trace_counter),deconvolvedCa_lambda_0(:,trace_counter)] = ...
        deconvolveCa(cal_traces_detrended(:,trace_counter), 'method', 'foopsi', 'type', 'exp2', ...
         'pars', taus, 'smin', 0, 'lambda', 0', 'optimize_pars', false, 'optimize_b', false); 
    [denoisedCa_lambda_0p2(:,trace_counter),deconvolvedCa_lambda_0p2(:,trace_counter)] = ...
        deconvolveCa(cal_traces_detrended(:,trace_counter), 'method', 'foopsi', 'type', 'exp2', ...
         'pars', taus, 'smin', 0, 'lambda', 0.2, 'optimize_pars', false, 'optimize_b', false);       
    [denoisedCa_lambda_0p4(:,trace_counter),deconvolvedCa_lambda_0p4(:,trace_counter)] = ...
        deconvolveCa(cal_traces_detrended(:,trace_counter), 'method', 'foopsi', 'type', 'exp2', ...
         'pars', taus, 'smin', 0, 'lambda', 0.4, 'optimize_pars', false, 'optimize_b', false);           
end
%%
% normalizing the deconvolved signals
d = exp(-1./taus(1));
r = exp(-1./taus(2));
deconvolvedCa_lambda_0 = deconvolvedCa_lambda_0 * (d - r);
deconvolvedCa_lambda_0p2 = deconvolvedCa_lambda_0p2 * (d - r);
deconvolvedCa_lambda_0p4 = deconvolvedCa_lambda_0p4 * (d - r);

save('deconv_union.mat', 'denoisedCa_lambda_0', 'deconvolvedCa_lambda_0', 'denoisedCa_lambda_0p2', 'deconvolvedCa_lambda_0p2', ...
        'denoisedCa_lambda_0p4', 'deconvolvedCa_lambda_0p4', 'baseline','-v7.3');

end
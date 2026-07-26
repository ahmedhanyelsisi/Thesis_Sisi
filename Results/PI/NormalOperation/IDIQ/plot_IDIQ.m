%% =========================================================================
%  PLOT_IDIQ.m
%  -------------------------------------------------------------------------
%  Purpose : Prompt the user to browse for a MAT file that contains the
%            Simulink SimulationOutput, then plot the d-axis (ID) and
%            q-axis (IQ) current signals.
%
%  File    : Selected interactively via a file-browser dialog
%  Object  : Simulink.SimulationOutput  ->  variable  "out"
%
%  Confirmed data layout (binary-verified, 2026-07-17)
%  ---------------------------------------------------
%    out.ID   -- single struct with fields:
%      .time              [1,500,001 x 1]  continuous sample timestamps (s)
%                         starts at 0, step = 1e-4 s  (100 us)
%      .signals           [1 x 2]  struct array:
%           signals(1)   ->  d-axis current (Id)
%                .values      [2501 x 600]  single (float32), mean~4.12 A
%           signals(2)   ->  q-axis current (Iq)
%                .values      [2501 x 600]  single (float32), mean~1.06 A
%      .blockName         source Simulink block path
%
%    Confirmed parameters:
%      Ts    = 1e-4 s  (100 us per sample)
%      nSamp = 600  samples per window
%      nWin  = 2501 windows
%      Total = 2501 x 600 = 1,500,600 samples per signal
%      Id mean ~ 4.12 A  |  Iq mean ~ 1.06 A  (binary-verified)
%
%  Author  : Auto-generated + debugged (v4 - time field fix, 2026-07-17)
%% =========================================================================

clearvars; clc; close all;

%% 1.  LOCATE AND LOAD THE MAT FILE
% Open a file-browser dialog so the user can pick any .mat file.
scriptDir = fileparts(mfilename('fullpath'));

[fileName, filePath] = uigetfile( ...
    {'*.mat', 'MAT-files (*.mat)'; '*.*', 'All Files (*.*)'}, ...
    'Select the MAT file containing the simulation data', ...
    scriptDir);          % start browser in the script folder by default

if isequal(fileName, 0)
    fprintf('No file selected. Script cancelled by user.\n');
    return;
end

matFile = fullfile(filePath, fileName);
fprintf('Loading: %s\n', matFile);

% The file contains a Simulink.SimulationOutput object named "out".
load(matFile, 'out');
fprintf('File loaded successfully.\n\n');

%% 2.  EXTRACT Id AND Iq SIGNAL DATA
%
%  CONFIRMED STRUCTURE (binary-verified 2026-07-17):
%
%    out.ID.signals   is a  [1 x 2]  struct array
%      signals(1).values  ->  Id  [nWin x nSamp]  single
%      signals(2).values  ->  Iq  [nWin x nSamp]  single
%
%    Time axis: out.ID.time  [1,500,001 x 1] float64, step = 1e-4 s
%
%  All methods attempt extraction in order; first success wins.

% Sampling period -- used by all methods and the heatmap
Ts_inner = 1e-4;   % 100 us per sample

id_data  = [];
iq_data  = [];
t        = [];
nWin     = 0;      % initialized here so heatmap is safe if Method 1 fails
nSamp    = 0;
tout     = [];     % initialized here so heatmap is safe if Method 1 fails

%% ---- Method 1:  out.ID.signals(1/2).values  (PRIMARY -- confirmed) ------
try
    ID_struct = out.ID;                        % single struct

    sig_arr = ID_struct.signals;               % [1 x 2] struct array
    n_sigs  = numel(sig_arr);

    if n_sigs >= 2
        % Extract Id from signals(1) and Iq from signals(2)
        id_vals = double(sig_arr(1).values);   % [nWin x nSamp]
        iq_vals = double(sig_arr(2).values);   % [nWin x nSamp]

    elseif n_sigs == 1
        % Only one signals element: check if values has 2 pages (3-D)
        vals = double(sig_arr(1).values);
        if size(vals, 3) >= 2
            id_vals = vals(:, :, 1);
            iq_vals = vals(:, :, 2);
        else
            id_vals = vals;
            iq_vals = vals;   % same — will warn below
            warning('PLOT_IDIQ:oneSig', ...
                'signals has only 1 element with 1 page; Id == Iq (check logging config).');
        end
    else
        error('signals struct array is empty.');
    end

    nWin  = size(id_vals, 1);             % rows  = windows
    nSamp = size(id_vals, 2);             % cols  = samples per window

    % Reshape [nWin x nSamp] -> column vector
    % Transpose first so samples within each window are contiguous:
    %   window1[s1..s600], window2[s1..s600], ...
    id_data = reshape(id_vals.', [], 1);       % nWin*nSamp x 1
    iq_data = reshape(iq_vals.', [], 1);

    % --- Time axis: use out.ID.time  (pre-built continuous time vector) ---
    % Binary-verified: [1,500,001 x 1] float64, starts at 0, step = 1e-4 s
    t_raw  = double(ID_struct.time(:));
    N_data = numel(id_data);
    N_time = numel(t_raw);

    if N_time >= N_data
        % Normal: trim time vector to match data length
        t = t_raw(1:N_data);
    elseif N_time > 1
        % Time slightly shorter — trim data to match
        id_data = id_data(1:N_time);
        iq_data = iq_data(1:N_time);
        t = t_raw;
        fprintf('  Note: time vector (%d) < data (%d); data trimmed.\n', N_time, N_data);
    else
        % time is scalar or empty — reconstruct from Ts_inner
        t = (0 : N_data-1).' * Ts_inner;
        fprintf('  Note: out.ID.time is scalar/empty; time reconstructed from Ts.\n');
    end

    fprintf('Method 1 (out.ID.signals(1/2).values) succeeded.\n');
    fprintf('  nWin=%d  nSamp=%d  total=%d  Id_mean=%.4f  Iq_mean=%.4f\n', ...
            nWin, nSamp, numel(id_data), mean(id_data,'omitnan'), mean(iq_data,'omitnan'));

catch ME1
    warning('PLOT_IDIQ:m1', 'Method 1 failed: %s', ME1.message);
end

%% ---- Method 2:  Simulink.SimulationData.Dataset  (logsout style) --------
if isempty(id_data)
    try
        ds      = out.get('ID');
        id_ts   = ds.get('id');
        iq_ts   = ds.get('iq');
        id_data = squeeze(double(id_ts.Values.Data));
        iq_data = squeeze(double(iq_ts.Values.Data));
        t       = id_ts.Values.Time;
        fprintf('Method 2 (SimulationData.Dataset) succeeded.\n');
    catch ME2
        warning('PLOT_IDIQ:m2', 'Method 2 failed: %s', ME2.message);
    end
end

%% ---- Method 3:  Direct timeseries on struct fields ----------------------
if isempty(id_data)
    try
        id_data = squeeze(double(out.ID.id.Values.Data));
        iq_data = squeeze(double(out.ID.iq.Values.Data));
        t       = out.ID.id.Values.Time;
        fprintf('Method 3 (timeseries on struct) succeeded.\n');
    catch ME3
        warning('PLOT_IDIQ:m3', 'Method 3 failed: %s', ME3.message);
    end
end

%% ---- Method 4:  3-D values array  [nWin x nSamp x 2] -------------------
if isempty(id_data)
    try
        vals = double(out.ID.signals.values);
        if ndims(vals) == 3 && size(vals, 3) >= 2
            id_data = reshape(vals(:,:,1).', [], 1);
            iq_data = reshape(vals(:,:,2).', [], 1);
        elseif size(vals, 2) >= 2
            id_data = vals(:, 1);
            iq_data = vals(:, 2);
        else
            id_data = vals(:);
            iq_data = vals(:);
        end
        nTotal = numel(id_data);
        t = (1:nTotal).' * Ts_inner;
        fprintf('Method 4 (3-D / 2-col values fallback) succeeded.\n');
    catch ME4
        warning('PLOT_IDIQ:m4', 'Method 4 failed: %s', ME4.message);
    end
end

%% ---- Abort if nothing worked --------------------------------------------
if isempty(id_data)
    error('PLOT_IDIQ:nodata', ...
        ['All extraction methods failed.\n' ...
         'Run debug_mat_structure.m in MATLAB to inspect the variable layout.\n' ...
         'Confirm the correct path to Id/Iq data and adapt Section 2.']);
end

% Guarantee column vectors
id_data = id_data(:);
iq_data = iq_data(:);
t       = t(:);

% Sanity check: warn if means look wrong (both signals should differ)
if abs(mean(id_data,'omitnan') - mean(iq_data,'omitnan')) < 0.01
    warning('PLOT_IDIQ:sameMean', ...
        'Id and Iq have nearly identical means (%.4f vs %.4f). Check extraction path.', ...
        mean(id_data,'omitnan'), mean(iq_data,'omitnan'));
end

%% 3.  BASIC VALIDATION AND STATISTICS
fprintf('\n---- Signal Statistics -----------------------------------------\n');
fprintf('  Samples   : %d per signal\n', numel(t));
fprintf('  Time axis : %.6f  to  %.4f  s   (step ~ %.2f us)\n', ...
        t(1), t(end), median(diff(t))*1e6);
fprintf('  Id  -- mean: %8.4f   std: %7.4f   min: %8.4f   max: %8.4f A\n', ...
        mean(id_data,'omitnan'), std(id_data,'omitnan'), ...
        min(id_data,[],'omitnan'), max(id_data,[],'omitnan'));
fprintf('  Iq  -- mean: %8.4f   std: %7.4f   min: %8.4f   max: %8.4f A\n', ...
        mean(iq_data,'omitnan'), std(iq_data,'omitnan'), ...
        min(iq_data,[],'omitnan'), max(iq_data,[],'omitnan'));
fprintf('----------------------------------------------------------------\n\n');

%% 4.  FIGURE 1: Separate Subplots  (Id top,  Iq bottom)
fig1 = figure('Name','ID and IQ Currents - Subplot View', ...
              'Color',[0.97 0.97 0.97], ...
              'NumberTitle','off', ...
              'Position',[80 80 1200 700]);

% -- Subplot 1: Id --
ax1 = subplot(2,1,1);
plot(t, id_data, 'Color',[0.00 0.45 0.74], 'LineWidth', 0.7);
hold on;
id_mean = mean(id_data,'omitnan');
yline(id_mean, '--r', 'LineWidth', 1.5, ...
      'Label', sprintf('Mean = %.4f A', id_mean), ...
      'LabelVerticalAlignment','bottom', ...
      'LabelHorizontalAlignment','right', ...
      'FontSize', 10);
hold off;
ylabel('I_d  (A)', 'FontSize', 12, 'FontWeight', 'bold');
title('D-Axis Current  ( I_d )', 'FontSize', 13, 'FontWeight', 'bold');
grid on;  grid minor;
xlim([t(1) t(end)]);
set(ax1, 'FontSize', 11, 'Box', 'on', 'GridAlpha', 0.3);
legend({'I_d  measured', 'Mean'}, 'Location', 'best', 'FontSize', 10);

% -- Subplot 2: Iq --
ax2 = subplot(2,1,2);
plot(t, iq_data, 'Color',[0.85 0.33 0.10], 'LineWidth', 0.7);
hold on;
iq_mean = mean(iq_data,'omitnan');
yline(iq_mean, '--b', 'LineWidth', 1.5, ...
      'Label', sprintf('Mean = %.4f A', iq_mean), ...
      'LabelVerticalAlignment','bottom', ...
      'LabelHorizontalAlignment','right', ...
      'FontSize', 10);
hold off;
ylabel('I_q  (A)', 'FontSize', 12, 'FontWeight', 'bold');
xlabel('Time  (s)', 'FontSize', 12, 'FontWeight', 'bold');
title('Q-Axis Current  ( I_q )', 'FontSize', 13, 'FontWeight', 'bold');
grid on;  grid minor;
xlim([t(1) t(end)]);
set(ax2, 'FontSize', 11, 'Box', 'on', 'GridAlpha', 0.3);
legend({'I_q  measured', 'Mean'}, 'Location', 'best', 'FontSize', 10);

sgtitle({'PI Controller  --  Normal Operation', ...
         sprintf('I_d / I_q Currents  |  %d samples per signal  |  Duration ~ %.2f s', ...
                 numel(t), t(end)-t(1))}, ...
        'FontSize', 14, 'FontWeight', 'bold');

linkaxes([ax1 ax2], 'x');

%% 5.  FIGURE 2: Overlay Plot  (Id and Iq together)
fig2 = figure('Name','ID and IQ Currents - Overlay', ...
              'Color',[0.97 0.97 0.97], ...
              'NumberTitle','off', ...
              'Position',[120 120 1200 500]);

plot(t, id_data, 'Color',[0.00 0.45 0.74], 'LineWidth', 0.7, 'DisplayName','I_d');
hold on;
plot(t, iq_data, 'Color',[0.85 0.33 0.10], 'LineWidth', 0.7, 'DisplayName','I_q');
yline(mean(id_data,'omitnan'), '--', 'Color',[0.00 0.45 0.74], 'LineWidth', 1.3, ...
      'DisplayName', sprintf('Mean I_d = %.4f A', mean(id_data,'omitnan')));
yline(mean(iq_data,'omitnan'), '--', 'Color',[0.85 0.33 0.10], 'LineWidth', 1.3, ...
      'DisplayName', sprintf('Mean I_q = %.4f A', mean(iq_data,'omitnan')));
hold off;
xlabel('Time  (s)',    'FontSize', 12, 'FontWeight', 'bold');
ylabel('Current  (A)', 'FontSize', 12, 'FontWeight', 'bold');
title({'PI Controller  --  Normal Operation  |  I_d and I_q Overlay', ...
       sprintf('100 us/sample  |  Duration ~ %.2f s  |  %d samples/signal', ...
               t(end)-t(1), numel(t))}, ...
      'FontSize', 13, 'FontWeight', 'bold');
legend('Location','best', 'FontSize',11);
grid on;  grid minor;
xlim([t(1) t(end)]);
set(gca,'FontSize',11,'Box','on','GridAlpha',0.3);

%% 6.  FIGURE 3: Per-Window Heatmap  (row = window,  col = sample index)
try
    % Retrieve window/sample dimensions robustly
    if exist('nWin','var') && exist('nSamp','var') && nWin > 1 && nSamp > 1
        nWin_hm  = nWin;
        nSamp_hm = nSamp;
    else
        % Fallback: infer from data size assuming nSamp=600
        nSamp_hm = 600;
        nWin_hm  = floor(numel(id_data) / nSamp_hm);
    end
    N_hm = nWin_hm * nSamp_hm;

    if numel(id_data) >= N_hm && nWin_hm > 1 && nSamp_hm > 1
        % Reshape column vectors back to [nWin x nSamp] matrices
        id_mat_hm = reshape(id_data(1:N_hm), nSamp_hm, nWin_hm).';
        iq_mat_hm = reshape(iq_data(1:N_hm), nSamp_hm, nWin_hm).';

        t_sample_ms = (1:nSamp_hm) * Ts_inner * 1e3;   % ms within window
        % Window axis: derive from the continuous time vector
        if numel(t) >= N_hm
            t_window_s = t(nSamp_hm : nSamp_hm : N_hm);  % end-of-window times
        else
            t_window_s = (1:nWin_hm) * (nSamp_hm * Ts_inner);
        end

        fig3 = figure('Name','ID / IQ Heatmaps (Window x Sample)', ...
                      'Color',[0.97 0.97 0.97], ...
                      'NumberTitle','off', ...
                      'Position',[160 160 1300 600]);

        subplot(1,2,1);
        imagesc(t_sample_ms, t_window_s, id_mat_hm);
        colormap(gca, parula);
        c1 = colorbar;   c1.Label.String = 'I_d (A)';   c1.Label.FontSize = 11;
        xlabel('Time within window  (ms)', 'FontSize',11,'FontWeight','bold');
        ylabel('Window end time  (s)',      'FontSize',11,'FontWeight','bold');
        title('I_d  -- Window \times Sample Heatmap','FontSize',12,'FontWeight','bold');
        set(gca,'FontSize',10,'YDir','normal');

        subplot(1,2,2);
        imagesc(t_sample_ms, t_window_s, iq_mat_hm);
        colormap(gca, parula);
        c2 = colorbar;   c2.Label.String = 'I_q (A)';   c2.Label.FontSize = 11;
        xlabel('Time within window  (ms)', 'FontSize',11,'FontWeight','bold');
        ylabel('Window end time  (s)',      'FontSize',11,'FontWeight','bold');
        title('I_q  -- Window \times Sample Heatmap','FontSize',12,'FontWeight','bold');
        set(gca,'FontSize',10,'YDir','normal');

        sgtitle('I_d / I_q Heatmaps  --  PI Normal Operation', ...
                'FontSize',13,'FontWeight','bold');
    end
catch ME_hm
    fprintf('Heatmap skipped: %s\n', ME_hm.message);
end

%% 7.  FIGURE 4: Zoomed View  (first 0.5 s)
fig4 = figure('Name','ID and IQ -- Zoomed First 0.5 s', ...
              'Color',[0.97 0.97 0.97], ...
              'NumberTitle','off', ...
              'Position',[200 200 1200 500]);

mask = t <= 0.5;
if sum(mask) < 2
    % Fewer than 2 points in first 0.5 s -> show first 5000 samples instead
    n_show = min(5000, numel(t));
    mask   = false(numel(t), 1);
    mask(1:n_show) = true;
end

plot(t(mask), id_data(mask), 'Color',[0.00 0.45 0.74], ...
     'LineWidth', 1.1, 'DisplayName','I_d');
hold on;
plot(t(mask), iq_data(mask), 'Color',[0.85 0.33 0.10], ...
     'LineWidth', 1.1, 'DisplayName','I_q');
hold off;
xlabel('Time  (s)',    'FontSize',12,'FontWeight','bold');
ylabel('Current  (A)', 'FontSize',12,'FontWeight','bold');
title({'Zoomed View -- First 0.5 s of I_d and I_q', ...
       'PI Controller  |  Normal Operation  |  100 us Sampling'}, ...
      'FontSize',13,'FontWeight','bold');
legend('Location','best','FontSize',11);
grid on;  grid minor;
set(gca,'FontSize',11,'Box','on','GridAlpha',0.3);

%% 8.  FIGURE 5: Amplitude Histograms
fig5 = figure('Name','ID / IQ Current Histograms', ...
              'Color',[0.97 0.97 0.97], ...
              'NumberTitle','off', ...
              'Position',[240 240 1100 480]);

subplot(1,2,1);
histogram(id_data(isfinite(id_data)), 80, ...
          'FaceColor',[0.00 0.45 0.74], 'EdgeAlpha',0.25);
xline(mean(id_data,'omitnan'), 'r--', 'LineWidth', 1.5, ...
      'Label', sprintf('Mean = %.4f A', mean(id_data,'omitnan')), 'FontSize',10);
xlabel('I_d  (A)',     'FontSize',11,'FontWeight','bold');
ylabel('Sample Count', 'FontSize',11,'FontWeight','bold');
title('I_d  Amplitude Distribution','FontSize',12,'FontWeight','bold');
grid on;  set(gca,'FontSize',10,'Box','on');

subplot(1,2,2);
histogram(iq_data(isfinite(iq_data)), 80, ...
          'FaceColor',[0.85 0.33 0.10], 'EdgeAlpha',0.25);
xline(mean(iq_data,'omitnan'), 'b--', 'LineWidth', 1.5, ...
      'Label', sprintf('Mean = %.4f A', mean(iq_data,'omitnan')), 'FontSize',10);
xlabel('I_q  (A)',     'FontSize',11,'FontWeight','bold');
ylabel('Sample Count', 'FontSize',11,'FontWeight','bold');
title('I_q  Amplitude Distribution','FontSize',12,'FontWeight','bold');
grid on;  set(gca,'FontSize',10,'Box','on');

sgtitle('Current Amplitude Histograms  --  PI Normal Operation', ...
        'FontSize',13,'FontWeight','bold');

%% 9.  DONE
fprintf('\nAll figures generated successfully.\n');
fprintf('Figures:\n');
fprintf('  Fig 1 -- Subplot view   (I_d and I_q separately with mean lines)\n');
fprintf('  Fig 2 -- Overlay view   (I_d and I_q on same axes)\n');
fprintf('  Fig 3 -- Heatmap        (window x sample index)\n');
fprintf('  Fig 4 -- Zoomed view    (first 0.5 s)\n');
fprintf('  Fig 5 -- Histograms     (amplitude distribution)\n');

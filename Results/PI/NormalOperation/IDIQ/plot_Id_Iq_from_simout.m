%% plot_Id_Iq_from_simout.m
%
% Loads a .mat file containing a Simulink simulation output variable
% named "out" (a Simulink.SimulationOutput object, or a plain struct
% with the same layout). Somewhere on "out" there is a "signals" 1x2
% struct array (either directly at out.signals, or nested under
% whatever variable name the model's Data Import/Export "Output"
% logging was configured with, e.g. out.ID.signals, out.yout.signals,
% out.logsout.signals, etc. -- the script searches for it automatically):
%
%   <found automatically>.signals(1).values  Id (direct-axis current)     -> NxM double array
%   <found automatically>.signals(2).values  Iq (quadrature-axis current) -> NxM double array
%
% Each ROW of the NxM array is one logged "packet": M samples taken
% Ts seconds apart. Rows are assumed to be in chronological order, so
% packet 1 = samples 1..M in time, packet 2 = samples M+1..2M, etc.
% This script "unwraps" each NxM matrix (row-by-row) into a single
% continuous time-domain vector, applies a 2nd-order Butterworth
% low-pass filter (fc = 200 Hz), and then produces:
%
%   Fig 1 - I_d vs time  (unfiltered light + filtered bold)
%   Fig 2 - I_q vs time  (unfiltered light + filtered bold)
%   Fig 3 - I_d and I_q overlay (unfiltered light + filtered bold, both signals)
%   Fig 4 - Amplitude histograms of I_d and I_q (raw + filtered distributions)
%   Console - basic statistics (mean/std/min/max) for both raw and filtered signals
%
% Filter: 2nd-order Butterworth, low-pass, fc = 200 Hz
%   Id and Iq are DC quantities in FOC, so 200 Hz cleanly removes
%   switching ripple while preserving all relevant transient dynamics.
%
% The script is not hard-coded to any fixed packet dimensions -- it reads
% the actual array dimensions from whatever file is selected, so it will
% work on any .mat file with the same structure (even if N or M differ).

clear; clc; close all;

%% =========================================================================
%  USER-CONFIGURABLE SETTINGS
%  =========================================================================
Ts       = 100e-6;   % sample time BETWEEN samples within a row/packet [s]
Fs       = 1 / Ts;   % sample rate [Hz]  -> 10 000 Hz

%  Butterworth low-pass filter parameters
filt_order  = 2;         % 2nd-order Butterworth
filt_cutoff = 200;       % cutoff frequency [Hz]
Wn          = filt_cutoff / (Fs/2);   % normalised cutoff (0 < Wn < 1)
[b_filt, a_filt] = butter(filt_order, Wn, 'low');

%% =========================================================================
%  LOAD FILE
%  =========================================================================
[fileName, filePath] = uigetfile('*.mat', 'Select the simulation output .mat file');
if isequal(fileName, 0)
    disp('No file selected. Exiting.');
    return;
end
fullFilePath = fullfile(filePath, fileName);

fprintf('Loading "%s" ...\n', fullFilePath);
loadedData = load(fullFilePath);

if ~isfield(loadedData, 'out')
    error(['The selected file does not contain a variable named "out". ' ...
           'Variables found: %s'], strjoin(fieldnames(loadedData), ', '));
end
out = loadedData.out;

%% =========================================================================
%  LOCATE THE "signals" STRUCT AUTOMATICALLY
%  =========================================================================
sig = getSignalsStruct(out);

if numel(sig) < 2
    error('Expected the "signals" struct to have at least 2 elements (Id, Iq); found %d.', numel(sig));
end

%% =========================================================================
%  EXTRACT AND VALIDATE Id / Iq PACKET MATRICES
%  =========================================================================
Id_raw = extractPacketMatrix(sig, 1, 'Id');
Iq_raw = extractPacketMatrix(sig, 2, 'Iq');

if ~isequal(size(Id_raw), size(Iq_raw))
    warning('Id size (%s) and Iq size (%s) do not match.', ...
        mat2str(size(Id_raw)), mat2str(size(Iq_raw)));
end

%% =========================================================================
%  UNWRAP EACH PACKET MATRIX -> CONTINUOUS TIME-DOMAIN VECTOR
%  reshape(X.',1,[]) reads X row-by-row (row 1 fully, then row 2, ...)
%  which gives samples in chronological order.
%  =========================================================================
Id = reshape(Id_raw.', 1, []);    % 1 x N row vector
Iq = reshape(Iq_raw.', 1, []);

%% =========================================================================
%  BUILD TIME VECTOR
%  =========================================================================
N              = numel(Id);
t              = (0:N-1) * Ts;          % [s]
numPackets     = size(Id_raw, 1);
samplesPerPack = size(Id_raw, 2);

fprintf('Loaded %d packets x %d samples/packet (%d samples total, %.3f s @ Ts = %g s).\n', ...
    numPackets, samplesPerPack, N, t(end), Ts);

%% =========================================================================
%  APPLY 2nd-ORDER BUTTERWORTH LOW-PASS FILTER  (fc = 200 Hz)
%  filtfilt() gives zero-phase filtering (no group-delay shift).
%  Id and Iq are DC quantities in FOC; 200 Hz removes switching/noise
%  ripple while preserving all relevant transient dynamics.
%  =========================================================================
Id_filt = filtfilt(b_filt, a_filt, Id);
Iq_filt = filtfilt(b_filt, a_filt, Iq);

fprintf('Filter applied: 2nd-order Butterworth low-pass, fc = %g Hz (zero-phase).\n\n', filt_cutoff);

%% =========================================================================
%  SIGNAL STATISTICS  (raw and filtered)
%  =========================================================================
% --- raw ---
idMean = mean(Id,'omitnan');  idStd = std(Id,'omitnan');
idMin  = min(Id);             idMax = max(Id);
iqMean = mean(Iq,'omitnan');  iqStd = std(Iq,'omitnan');
iqMin  = min(Iq);             iqMax = max(Iq);

% --- filtered ---
idMeanF = mean(Id_filt,'omitnan');  idStdF = std(Id_filt,'omitnan');
idMinF  = min(Id_filt);             idMaxF = max(Id_filt);
iqMeanF = mean(Iq_filt,'omitnan');  iqStdF = std(Iq_filt,'omitnan');
iqMinF  = min(Iq_filt);             iqMaxF = max(Iq_filt);

fprintf('---- Signal Statistics -------------------------------------------\n');
fprintf('  %-26s  %8s  %8s  %8s  %8s\n', '', 'Mean', 'Std', 'Min', 'Max');
fprintf('  %-26s  %8.4f  %8.4f  %8.4f  %8.4f  (A)\n', 'I_d  raw',      idMean,  idStd,  idMin,  idMax);
fprintf('  %-26s  %8.4f  %8.4f  %8.4f  %8.4f  (A)\n', 'I_d  filtered',  idMeanF, idStdF, idMinF, idMaxF);
fprintf('  %-26s  %8.4f  %8.4f  %8.4f  %8.4f  (A)\n', 'I_q  raw',      iqMean,  iqStd,  iqMin,  iqMax);
fprintf('  %-26s  %8.4f  %8.4f  %8.4f  %8.4f  (A)\n', 'I_q  filtered',  iqMeanF, iqStdF, iqMinF, iqMaxF);
fprintf('-------------------------------------------------------------------\n\n');

%% =========================================================================
%  COLOUR PALETTE
%  =========================================================================
colorId      = [0.00 0.45 0.74];      % blue   (bold line)
colorIq      = [0.85 0.33 0.10];      % orange (bold line)
colorIdLight = [0.55 0.75 0.90];      % pale blue   (raw/unfiltered)
colorIqLight = [0.97 0.72 0.57];      % pale orange (raw/unfiltered)
alphaRaw     = 0.55;                  % transparency of raw line

lineWidthRaw    = 0.6;
lineWidthFilt   = 1.6;
lineWidthMean   = 1.4;

%% =========================================================================
%  FIGURE 1 -- I_d vs time  (unfiltered + filtered)
%  =========================================================================
fig1 = figure('Name', 'Id - Direct Axis Current', ...
              'NumberTitle', 'off', ...
              'Color', [0.97 0.97 0.97], ...
              'Position', [80 80 1200 500]);

% Raw (light, behind)
hRaw1 = plot(t, Id, 'Color', [colorIdLight, alphaRaw], ...
             'LineWidth', lineWidthRaw, 'DisplayName', 'I_d  raw');
hold on;

% Filtered (bold, foreground)
hFilt1 = plot(t, Id_filt, 'Color', colorId, ...
              'LineWidth', lineWidthFilt, 'DisplayName', ...
              sprintf('I_d  filtered  (2nd Butterworth, f_c = %g Hz)', filt_cutoff));

% Mean line on filtered signal
yline(idMeanF, '--r', 'LineWidth', lineWidthMean, ...
      'Label', sprintf('Mean = %.4f A', idMeanF), ...
      'LabelHorizontalAlignment', 'right', ...
      'LabelVerticalAlignment',   'bottom', 'FontSize', 9);
hold off;

grid on; grid minor;
xlabel('Time  (s)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('I_d  (A)',  'FontSize', 12, 'FontWeight', 'bold');
title({'Direct-Axis Current  I_d  vs Time', ...
       sprintf('%d samples  |  Duration %.3f s  |  Ts = %g µs', N, t(end), Ts*1e6)}, ...
      'FontSize', 13, 'FontWeight', 'bold');
legend([hRaw1, hFilt1], 'Location', 'best', 'FontSize', 10);
xlim([t(1) t(end)]);
set(gca, 'Box', 'on', 'GridAlpha', 0.3, 'FontSize', 11);

%% =========================================================================
%  FIGURE 2 -- I_q vs time  (unfiltered + filtered)
%  =========================================================================
fig2 = figure('Name', 'Iq - Quadrature Axis Current', ...
              'NumberTitle', 'off', ...
              'Color', [0.97 0.97 0.97], ...
              'Position', [100 100 1200 500]);

hRaw2 = plot(t, Iq, 'Color', [colorIqLight, alphaRaw], ...
             'LineWidth', lineWidthRaw, 'DisplayName', 'I_q  raw');
hold on;

hFilt2 = plot(t, Iq_filt, 'Color', colorIq, ...
              'LineWidth', lineWidthFilt, 'DisplayName', ...
              sprintf('I_q  filtered  (2nd Butterworth, f_c = %g Hz)', filt_cutoff));

yline(iqMeanF, '--b', 'LineWidth', lineWidthMean, ...
      'Label', sprintf('Mean = %.4f A', iqMeanF), ...
      'LabelHorizontalAlignment', 'right', ...
      'LabelVerticalAlignment',   'bottom', 'FontSize', 9);
hold off;

grid on; grid minor;
xlabel('Time  (s)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('I_q  (A)',  'FontSize', 12, 'FontWeight', 'bold');
title({'Quadrature-Axis Current  I_q  vs Time', ...
       sprintf('%d samples  |  Duration %.3f s  |  Ts = %g µs', N, t(end), Ts*1e6)}, ...
      'FontSize', 13, 'FontWeight', 'bold');
legend([hRaw2, hFilt2], 'Location', 'best', 'FontSize', 10);
xlim([t(1) t(end)]);
set(gca, 'Box', 'on', 'GridAlpha', 0.3, 'FontSize', 11);

%% =========================================================================
%  FIGURE 3 -- I_d and I_q overlay  (unfiltered light + filtered bold)
%  =========================================================================
fig3 = figure('Name', 'Id and Iq - Overlay', ...
              'NumberTitle', 'off', ...
              'Color', [0.97 0.97 0.97], ...
              'Position', [120 120 1200 540]);

% -- Raw signals (light, plotted first so filtered draws on top) --
hR_d = plot(t, Id, 'Color', [colorIdLight, alphaRaw], ...
            'LineWidth', lineWidthRaw, 'DisplayName', 'I_d  raw');
hold on;
hR_q = plot(t, Iq, 'Color', [colorIqLight, alphaRaw], ...
            'LineWidth', lineWidthRaw, 'DisplayName', 'I_q  raw');

% -- Filtered signals (bold) --
hF_d = plot(t, Id_filt, 'Color', colorId, ...
            'LineWidth', lineWidthFilt, 'DisplayName', 'I_d  filtered');
hF_q = plot(t, Iq_filt, 'Color', colorIq, ...
            'LineWidth', lineWidthFilt, 'DisplayName', 'I_q  filtered');

% -- Mean lines on filtered --
yline(idMeanF, '--', 'Color', colorId, 'LineWidth', lineWidthMean, ...
      'DisplayName', sprintf('Mean I_d = %.4f A', idMeanF));
yline(iqMeanF, '--', 'Color', colorIq, 'LineWidth', lineWidthMean, ...
      'DisplayName', sprintf('Mean I_q = %.4f A', iqMeanF));
hold off;

grid on; grid minor;
xlabel('Time  (s)',    'FontSize', 12, 'FontWeight', 'bold');
ylabel('Current  (A)', 'FontSize', 12, 'FontWeight', 'bold');
title({sprintf('I_d and I_q Overlay  |  2nd-order Butterworth LP filter  |  f_c = %g Hz', filt_cutoff), ...
       sprintf('%d samples  |  Duration %.3f s  |  Ts = %g µs', N, t(end), Ts*1e6)}, ...
      'FontSize', 13, 'FontWeight', 'bold');
legend([hR_d, hR_q, hF_d, hF_q], 'Location', 'best', 'FontSize', 10);
xlim([t(1) t(end)]);
set(gca, 'Box', 'on', 'GridAlpha', 0.3, 'FontSize', 11);

%% =========================================================================
%  FIGURE 4 -- Amplitude histograms  (raw + filtered side-by-side)
%  =========================================================================
fig4 = figure('Name', 'Id / Iq Histograms', ...
              'NumberTitle', 'off', ...
              'Color', [0.97 0.97 0.97], ...
              'Position', [160 160 1100 520]);

% -- I_d histogram --
subplot(1, 2, 1);
histogram(Id(isfinite(Id)),        80, 'FaceColor', colorIdLight, ...
          'EdgeAlpha', 0.15, 'DisplayName', 'I_d  raw');
hold on;
histogram(Id_filt(isfinite(Id_filt)), 80, 'FaceColor', colorId, ...
          'EdgeAlpha', 0.20, 'FaceAlpha', 0.70, 'DisplayName', 'I_d  filtered');
xline(idMean,  '--', 'Color', colorIdLight, 'LineWidth', 1.4, ...
      'Label', sprintf('Mean raw = %.4f A', idMean),      'FontSize', 8);
xline(idMeanF, '--', 'Color', colorId,      'LineWidth', 1.6, ...
      'Label', sprintf('Mean filt = %.4f A', idMeanF),   'FontSize', 9);
hold off;
xlabel('I_d  (A)',     'FontSize', 11, 'FontWeight', 'bold');
ylabel('Sample Count', 'FontSize', 11, 'FontWeight', 'bold');
title('I_d  Amplitude Distribution', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best', 'FontSize', 9);
grid on;
set(gca, 'Box', 'on', 'FontSize', 10);

% -- I_q histogram --
subplot(1, 2, 2);
histogram(Iq(isfinite(Iq)),        80, 'FaceColor', colorIqLight, ...
          'EdgeAlpha', 0.15, 'DisplayName', 'I_q  raw');
hold on;
histogram(Iq_filt(isfinite(Iq_filt)), 80, 'FaceColor', colorIq, ...
          'EdgeAlpha', 0.20, 'FaceAlpha', 0.70, 'DisplayName', 'I_q  filtered');
xline(iqMean,  '--', 'Color', colorIqLight, 'LineWidth', 1.4, ...
      'Label', sprintf('Mean raw = %.4f A', iqMean),      'FontSize', 8);
xline(iqMeanF, '--', 'Color', colorIq,      'LineWidth', 1.6, ...
      'Label', sprintf('Mean filt = %.4f A', iqMeanF),   'FontSize', 9);
hold off;
xlabel('I_q  (A)',     'FontSize', 11, 'FontWeight', 'bold');
ylabel('Sample Count', 'FontSize', 11, 'FontWeight', 'bold');
title('I_q  Amplitude Distribution', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best', 'FontSize', 9);
grid on;
set(gca, 'Box', 'on', 'FontSize', 10);

sgtitle({'Current Amplitude Histograms  --  Raw vs Filtered', ...
         sprintf('2nd-order Butterworth LP  |  f_c = %g Hz  |  Fs = %g Hz', ...
                 filt_cutoff, Fs)}, ...
        'FontSize', 13, 'FontWeight', 'bold');

%% =========================================================================
%  DONE
%  =========================================================================
fprintf('All 4 figures generated.\n');
fprintf('  Fig 1 -- I_d vs time          (raw light + filtered bold)\n');
fprintf('  Fig 2 -- I_q vs time          (raw light + filtered bold)\n');
fprintf('  Fig 3 -- I_d & I_q overlay    (raw light + filtered bold, both signals)\n');
fprintf('  Fig 4 -- Amplitude histograms (raw + filtered distributions)\n');

%% ======================================================================
%  ALTERNATIVE VISUALIZATIONS (uncomment whichever you'd prefer)
%  ======================================================================

% --- (A) Overlay every packet on the same axes (scope-persistence view) ---
% tPacket = (0:samplesPerPack-1) * Ts;
% figure('Name', 'Id - All packets overlaid');
% plot(tPacket, Id_raw', 'Color', colorIdLight); grid on;
% xlabel('Time within packet (s)'); ylabel('I_d (A)');
% title('I_d - all packets overlaid');
%
% figure('Name', 'Iq - All packets overlaid');
% plot(tPacket, Iq_raw', 'Color', colorIqLight); grid on;
% xlabel('Time within packet (s)'); ylabel('I_q (A)');
% title('I_q - all packets overlaid');

% --- (B) 2-D image/heatmap view: packet index vs. sample-in-packet ---
% figure('Name', 'Id - packet heatmap');
% imagesc(Id_raw); axis xy; colorbar;
% xlabel('Sample within packet'); ylabel('Packet index');
% title('I_d heatmap (packet vs sample)');
%
% figure('Name', 'Iq - packet heatmap');
% imagesc(Iq_raw); axis xy; colorbar;
% xlabel('Sample within packet'); ylabel('Packet index');
% title('I_q heatmap (packet vs sample)');

%% ======================================================================
%  LOCAL FUNCTIONS
%  ======================================================================
function sig = getSignalsStruct(out)
% Finds a struct with a "signals" field, checking out.signals directly
% first, then scanning every property/field of "out" for a substruct
% that has one (e.g. out.ID.signals, out.yout.signals, ...).

    % --- Try the direct property first ---
    sig = tryGetField(out, 'signals');
    if ~isempty(sig)
        fprintf('Using out.signals\n');
        return;
    end

    % --- Fall back: scan every property/field of "out" ---
    if isobject(out)
        names = properties(out);
    else
        names = fieldnames(out);
    end

    for k = 1:numel(names)
        name = names{k};
        try
            val = out.(name);
        catch
            continue;
        end
        if isstruct(val) && isfield(val, 'signals') && numel(val.signals) >= 1
            sig = val.signals;
            fprintf('Using out.%s.signals\n', name);
            return;
        end
    end

    error(['Could not locate a "signals" struct anywhere on "out". ' ...
           'Properties/fields found on out: %s. ' ...
           'In MATLAB, type "out" and "properties(out)" (or "fieldnames(out)") ' ...
           'to see what''s available, then tell me the correct path so I can update the script.'], ...
           strjoin(names, ', '));
end

function val = tryGetField(s, name)
% Returns s.(name) if it exists and is non-empty, otherwise [].
    val = [];
    try
        w = warning('off', 'all');
        candidate = s.(name);
        warning(w);
        if ~isempty(candidate)
            val = candidate;
        end
    catch
        val = [];
    end
end

function values = extractPacketMatrix(sig, idx, label)
% Pulls out sig(idx).values, validates it, and returns it as double.
    if idx > numel(sig)
        error('The signals struct does not have an element #%d for %s.', idx, label);
    end
    try
        values = sig(idx).values;
    catch ME
        error('Could not access signals(%d).values (%s): %s', idx, label, ME.message);
    end
    if isempty(values) || ~isnumeric(values) || ~ismatrix(values)
        error('signals(%d).values (%s) is not a non-empty 2-D numeric array.', idx, label);
    end
    values = double(values);   % cast single -> double if needed
end

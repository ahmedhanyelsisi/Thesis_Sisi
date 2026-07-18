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
%   <found automatically>.signals(2).values  Iq (quadrature-axis current)  -> NxM double array
%
% Each ROW of the NxM array is one logged "packet": M samples taken
% Ts seconds apart. Rows are assumed to be in chronological order, so
% packet 1 = samples 1..M in time, packet 2 = samples M+1..2M, etc.
% This script "unwraps" each NxM matrix (row-by-row) into a single
% continuous time-domain vector and then produces:
%
%   Fig 1 - I_d vs time (individual, raw + filtered)
%   Fig 2 - I_q vs time (individual, raw + filtered)
%   Fig 3 - I_d and I_q together on one plot (overlay, raw + filtered)
%   Fig 4 - Amplitude histograms of I_d and I_q (raw + filtered)
%   Console - basic statistics (mean/std/min/max) for both signals
%
% The script reads the actual array dimensions from whatever file is selected, 
% so it will work on any .mat file with the same structure.

clear; clc; close all;

%% --- User-configurable settings ---
Ts = 100e-6;        % sample time BETWEEN SAMPLES WITHIN A ROW/PACKET [s]
Fc = 200;           % Filter cutoff frequency [Hz]

%% --- Prompt user to select a .mat file ---
[fileName, filePath] = uigetfile('*.mat', 'Select the simulation output .mat file');
if isequal(fileName, 0)
    disp('No file selected. Exiting.');
    return;
end
fullFilePath = fullfile(filePath, fileName);

%% --- Load the file ---
fprintf('Loading "%s" ...\n', fullFilePath);
loadedData = load(fullFilePath);

if ~isfield(loadedData, 'out')
    error(['The selected file does not contain a variable named "out". ' ...
           'Variables found: %s'], strjoin(fieldnames(loadedData), ', '));
end
out = loadedData.out;

%% --- Locate the "signals" struct, wherever it lives on "out" ---
sig = getSignalsStruct(out);

if numel(sig) < 2
    error('Expected the "signals" struct to have at least 2 elements (Id, Iq); found %d.', numel(sig));
end

%% --- Extract and validate Id / Iq packet matrices ---
Id_raw = extractPacketMatrix(sig, 1, 'Id');
Iq_raw = extractPacketMatrix(sig, 2, 'Iq');

if ~isequal(size(Id_raw), size(Iq_raw))
    warning('Id size (%s) and Iq size (%s) do not match.', ...
        mat2str(size(Id_raw)), mat2str(size(Iq_raw)));
end

%% --- Unwrap each packet matrix into one continuous time-domain vector ---
% Cast to double here to ensure filtfilt and other functions do not throw datatype errors
Id = double(reshape(Id_raw.', 1, []));
Iq = double(reshape(Iq_raw.', 1, []));

%% --- Build the time vector & Apply Butterworth Filter ---
N = numel(Id);
t = (0:N-1) * Ts;   % seconds
Fs = 1/Ts;          % Sampling frequency [Hz]

numPackets     = size(Id_raw, 1);
samplesPerPack = size(Id_raw, 2);
fprintf('Loaded %d packets x %d samples/packet (%d samples total, %.3f s @ Ts = %g s).\n', ...
    numPackets, samplesPerPack, N, t(end), Ts);

% Design and apply 2nd-order Butterworth filter
Wn = Fc / (Fs/2); % Normalized cutoff frequency
if Wn >= 1
    warning('Cutoff frequency %g Hz is above or equal to the Nyquist frequency %g Hz. Skipping filtering.', Fc, Fs/2);
    Id_filt = Id;
    Iq_filt = Iq;
else
    [b, a] = butter(2, Wn);
    % Using filtfilt for zero-phase distortion (preserves time alignment)
    Id_filt = filtfilt(b, a, Id);
    Iq_filt = filtfilt(b, a, Iq);
end

%% --- Colors used throughout, for a consistent look across all figures ---
colorId       = [0.00 0.45 0.74];   % blue (Filtered)
colorId_light = [0.65 0.82 0.95];   % light blue (Unfiltered)
colorIq       = [0.85 0.33 0.10];   % orange (Filtered)
colorIq_light = [0.96 0.73 0.62];   % light orange (Unfiltered)

%% --- Signal statistics (Filtered) ---
idMean = mean(Id_filt, 'omitnan');  idStd = std(Id_filt, 'omitnan');
idMin  = min(Id_filt);              idMax = max(Id_filt);
iqMean = mean(Iq_filt, 'omitnan');  iqStd = std(Iq_filt, 'omitnan');
iqMin  = min(Iq_filt);              iqMax = max(Iq_filt);

fprintf('\n---- Filtered Signal Statistics (%d Hz Cutoff) --------------------\n', Fc);
fprintf('  Samples   : %d per signal (%.3f s @ Ts = %g s)\n', N, t(end), Ts);
fprintf('  I_d  -- mean: %8.4f   std: %7.4f   min: %8.4f   max: %8.4f (A)\n', idMean, idStd, idMin, idMax);
fprintf('  I_q  -- mean: %8.4f   std: %7.4f   min: %8.4f   max: %8.4f (A)\n', iqMean, iqStd, iqMin, iqMax);
fprintf('--------------------------------------------------------------------\n\n');

%% --- Figure 1: Id (individual) ---
figure('Name', 'Id - Direct Axis Current', 'NumberTitle', 'off', 'Color', [0.97 0.97 0.97]);
plot(t, Id, 'Color', colorId_light, 'LineWidth', 0.5, 'DisplayName', 'I_d (Raw)'); hold on;
plot(t, Id_filt, 'Color', colorId, 'LineWidth', 1.2, 'DisplayName', sprintf('I_d (Filtered %dHz)', Fc));
yline(idMean, '--r', 'LineWidth', 1.3, 'Label', sprintf('Mean = %.4f A', idMean), ...
    'LabelHorizontalAlignment', 'right', 'FontSize', 9, 'HandleVisibility', 'off');
hold off;
grid on; grid minor;
xlabel('Time (s)');
ylabel('I_d (A)');
title('Direct Axis Current I_d vs Time');
legend('Location', 'best');
xlim([t(1) t(end)]);
set(gca, 'Box', 'on', 'GridAlpha', 0.3);

%% --- Figure 2: Iq (individual) ---
figure('Name', 'Iq - Quadrature Axis Current', 'NumberTitle', 'off', 'Color', [0.97 0.97 0.97]);
plot(t, Iq, 'Color', colorIq_light, 'LineWidth', 0.5, 'DisplayName', 'I_q (Raw)'); hold on;
plot(t, Iq_filt, 'Color', colorIq, 'LineWidth', 1.2, 'DisplayName', sprintf('I_q (Filtered %dHz)', Fc));
yline(iqMean, '--b', 'LineWidth', 1.3, 'Label', sprintf('Mean = %.4f A', iqMean), ...
    'LabelHorizontalAlignment', 'right', 'FontSize', 9, 'HandleVisibility', 'off');
hold off;
grid on; grid minor;
xlabel('Time (s)');
ylabel('I_q (A)');
title('Quadrature Axis Current I_q vs Time');
legend('Location', 'best');
xlim([t(1) t(end)]);
set(gca, 'Box', 'on', 'GridAlpha', 0.3);

%% --- Figure 3: Id and Iq together (overlay) ---
figure('Name', 'Id and Iq - Overlay', 'NumberTitle', 'off', 'Color', [0.97 0.97 0.97], ...
       'Position', [120 120 1100 500]);
plot(t, Id, 'Color', colorId_light, 'LineWidth', 0.5, 'DisplayName', 'I_d (Raw)'); hold on;
plot(t, Iq, 'Color', colorIq_light, 'LineWidth', 0.5, 'DisplayName', 'I_q (Raw)');
plot(t, Id_filt, 'Color', colorId, 'LineWidth', 1.2, 'DisplayName', sprintf('I_d (Filtered %dHz)', Fc)); 
plot(t, Iq_filt, 'Color', colorIq, 'LineWidth', 1.2, 'DisplayName', sprintf('I_q (Filtered %dHz)', Fc));
yline(idMean, '--', 'Color', colorId, 'LineWidth', 1.2, ...
    'DisplayName', sprintf('Mean I_d = %.4f A', idMean));
yline(iqMean, '--', 'Color', colorIq, 'LineWidth', 1.2, ...
    'DisplayName', sprintf('Mean I_q = %.4f A', iqMean));
hold off;
grid on; grid minor;
xlabel('Time (s)');
ylabel('Current (A)');
title(sprintf('I_d and I_q Overlay  |  %d samples  |  Duration %.3f s', N, t(end)));
legend('Location', 'best', 'NumColumns', 2);
xlim([t(1) t(end)]);
set(gca, 'Box', 'on', 'GridAlpha', 0.3);

%% --- Figure 4: Amplitude histograms ---
figure('Name', 'Id / Iq Histograms', 'NumberTitle', 'off', 'Color', [0.97 0.97 0.97], ...
       'Position', [160 160 1000 450]);

subplot(1,2,1);
histogram(Id(isfinite(Id)), 80, 'FaceColor', colorId_light, 'EdgeAlpha', 0.1, 'DisplayName', 'Raw'); hold on;
histogram(Id_filt(isfinite(Id_filt)), 80, 'FaceColor', colorId, 'EdgeAlpha', 0.4, 'DisplayName', 'Filtered');
xline(idMean, 'r--', 'LineWidth', 1.4, 'Label', sprintf('Mean = %.4f A', idMean), 'HandleVisibility', 'off');
xlabel('I_d (A)');
ylabel('Sample Count');
title('I_d Amplitude Distribution');
legend('Location', 'best');
grid on;
set(gca, 'Box', 'on');

subplot(1,2,2);
histogram(Iq(isfinite(Iq)), 80, 'FaceColor', colorIq_light, 'EdgeAlpha', 0.1, 'DisplayName', 'Raw'); hold on;
histogram(Iq_filt(isfinite(Iq_filt)), 80, 'FaceColor', colorIq, 'EdgeAlpha', 0.4, 'DisplayName', 'Filtered');
xline(iqMean, 'b--', 'LineWidth', 1.4, 'Label', sprintf('Mean = %.4f A', iqMean), 'HandleVisibility', 'off');
xlabel('I_q (A)');
ylabel('Sample Count');
title('I_q Amplitude Distribution');
legend('Location', 'best');
grid on;
set(gca, 'Box', 'on');

sgtitle('Current Amplitude Histograms (Raw vs Filtered)');

%% ======================================================================
%  Local functions
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
% Swallows errors/warnings from accessing a non-existent property.
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
% Pulls out sig(idx).values, checks it exists and is a non-empty 2-D
% numeric array, and returns it.
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
end
%% plot_scope_data.m
% Reads an oscilloscope CSV export, runs an FFT-based ripple/harmonic
% analysis on both DC signals (referenced to the known line and
% converter switching frequencies), low-pass filters them for display,
% and produces two figures:
%   Figure 1 - Vdc and Iload, each as a stacked subplot (raw + filtered)
%   Figure 2 - FFT amplitude spectrum of raw Vdc and raw Iload, with the
%              line frequency, its low multiples (incl. 100 Hz), and the
%              switching frequency marked
%   CH1 -> DC link voltage   (raw CSV reading must be multiplied by 10)
%   CH2 -> Load current      (DC value, used as-is, no scaling)
%
% Expected CSV layout (typical scope "Waveform Data" export):
%   Col 1 : Time for CH1 (s)
%   Col 2 : CH1 raw value      -> Vdc = Col2 * 10
%   Col 3 : Time for CH2 (s)   (same time base as Col 1)
%   Col 4 : CH2 raw value      -> Iload = Col4 (no scaling)
%   Col 5 : empty (file has a trailing comma) - ignored
%
% The script locates the "Waveform Data" marker line so it will still
% work even if the instrument header block has a different length.

clear; clc; close all;

%% ---- USER SETTINGS: low-pass filter ----
% Both channels are nominally DC, so this filter removes ripple/noise
% while preserving the underlying trend. Tune cutoffFreq to sit below
% your known ripple/switching-noise frequency and above the frequency
% content of any real transient you want to keep.
filterOrder = 2;      % Butterworth filter order (2nd order is a good default)
cutoffFreq  = 200;    % Low-pass cutoff frequency (Hz)

% Known ripple sources for the FFT-based harmonic analysis below.
lineFreq   = 50;      % Hz - AC supply/line frequency
switchFreq = 10000;   % Hz - converter switching frequency

%% ---- 1. Ask the user for the CSV file ----
filename = '';

% Try a graphical file picker first (desktop MATLAB)
try
    [file, filepath] = uigetfile({'*.csv;*.CSV', 'CSV files (*.csv)'}, ...
                                  'Select the oscilloscope CSV file');
    if ~isequal(file, 0)
        filename = fullfile(filepath, file);
    end
catch
    % No graphical display available (e.g. -nodisplay) -> fall through
end

% Fall back to typed input if no file was picked (or dialog unavailable)
while isempty(filename)
    filename = strtrim(input('Enter the full path to the CSV file: ', 's'));
    filename = strrep(filename, '"', '');   % strip stray quotes if pasted
    if isempty(filename) || ~isfile(filename)
        fprintf('File not found: "%s". Please try again.\n', filename);
        filename = '';
    end
end

fprintf('Loading: %s\n', filename);

%% ---- 2. Find where the instrument header ends ----
fid = fopen(filename, 'r');
if fid == -1
    error('Could not open file: %s', filename);
end

headerLines = 0;
foundMarker = false;
while true
    line = fgetl(fid);
    if ~ischar(line)
        break;                          % reached end of file
    end
    headerLines = headerLines + 1;
    if startsWith(strtrim(line), 'Waveform Data', 'IgnoreCase', true)
        foundMarker = true;
        break;                          % data starts on the next line
    end
end
fclose(fid);

if ~foundMarker
    warning(['"Waveform Data" marker not found. The header format may ' ...
             'differ from what this script expects; attempting to read ' ...
             'numeric data from line %d anyway.'], headerLines + 1);
end

%% ---- 3. Read the numeric waveform data ----
data = readmatrix(filename, 'NumHeaderLines', headerLines, 'Delimiter', ',');

if isempty(data) || size(data, 2) < 4
    error(['No valid 4-column numeric data was found after the header. ' ...
           'Please check that the file matches the expected format.']);
end

time    = data(:, 1);   % seconds (CH1 and CH2 share the same time base)
ch1_raw = data(:, 2);   % raw CH1 reading
ch2_raw = data(:, 4);   % raw CH2 reading

%% ---- 4. Apply the known scaling ----
Vdc   = ch1_raw * 10;   % DC link voltage: every CH1 reading is x10
Iload = ch2_raw;        % Load current: already correct, no scaling

%% ---- 5. FFT-based ripple/harmonic analysis of Vdc and Iload ----
% Vdc and Iload are still DC quantities -- there's no AC "fundamental"
% to normalize against the way the grid script normalized against
% 50 Hz, so every component below is still reported as a percentage of
% the DC mean, not of some AC fundamental. What FFT buys here is the
% ability to see WHICH frequencies the ripple sits at, rather than
% only a single lumped number -- specifically: the line frequency and
% its low multiples (2x = 100 Hz is the classic signature of a supply
% imbalance/unbalance feeding a rectifier; 6x = 300 Hz is the normal
% ripple of a balanced 6-pulse bridge), plus the converter's switching
% frequency and its neighborhood.
%
% Amplitudes are read from a Hann-windowed FFT (reduces spectral
% leakage from a non-integer number of captured cycles), searching a
% small tolerance band around each target frequency. Computed from the
% RAW signal, not the filtered one, for the same reason as before:
% filtering removes exactly the ripple this analysis is trying to see.
try
    hann(4, 'periodic'); %#ok<NASGU>
    butter(1, 0.1, 'low'); %#ok<NASGU>
catch ME
    error(['This section requires the Signal Processing Toolbox (hann, ' ...
           'butter, filtfilt). Original error: %s'], ME.message);
end

Fs = 1 / mean(diff(time));     % sampling frequency detected from the data (Hz)
nyquist = Fs / 2;
fprintf('Detected sample rate: %.1f Hz (Nyquist = %.1f Hz)\n', Fs, nyquist);

if switchFreq >= nyquist
    warning(['Switching frequency (%.0f Hz) is at or above the Nyquist limit ' ...
             '(%.1f Hz) for this capture, so switching-frequency content in ' ...
             'the FFT is unreliable/aliased at this sample rate. Line-frequency ' ...
             'ripple (50/100/150/300 Hz) is still valid.'], switchFreq, nyquist);
end

[freqVdc,   specVdc]   = singleSidedSpectrum(Vdc,   Fs);
[freqIload, specIload] = singleSidedSpectrum(Iload, Fs);

dcVdc   = mean(Vdc,   'omitnan');
dcIload = mean(Iload, 'omitnan');

% --- Named components of interest (dropping anything above Nyquist) ---
compFreqs  = [lineFreq, 2*lineFreq, 3*lineFreq, 6*lineFreq, switchFreq];
compLabels = {'Line (50 Hz)', '2x Line (100 Hz, supply imbalance signature)', ...
              '3x Line (150 Hz)', '6x Line (300 Hz, normal 6-pulse ripple)', ...
              sprintf('Switching (%.0f Hz)', switchFreq)};
keep       = compFreqs < nyquist;
compFreqs  = compFreqs(keep);
compLabels = compLabels(keep);

freqRes = Fs / numel(time);
tolHz   = max(3 * freqRes, 2);

ampVdc   = zeros(1, numel(compFreqs));
ampIload = zeros(1, numel(compFreqs));
for k = 1:numel(compFreqs)
    ampVdc(k)   = peakNear(freqVdc,   specVdc,   compFreqs(k), tolHz);
    ampIload(k) = peakNear(freqIload, specIload, compFreqs(k), tolHz);
end
pctVdc   = 100 * ampVdc   / abs(dcVdc);
pctIload = 100 * ampIload / abs(dcIload);

% --- Overall ripple, all AC content combined (time-domain, exact) ---
rippleVdc   = 100 * std(Vdc,   'omitnan') / abs(dcVdc);
rippleIload = 100 * std(Iload, 'omitnan') / abs(dcIload);

fprintf('\n---- Ripple / harmonic content (%% of DC mean) --------------------\n');
for k = 1:numel(compFreqs)
    fprintf('  %-46s V_dc: %6.3f %%    I_load: %6.3f %%\n', ...
            compLabels{k}, pctVdc(k), pctIload(k));
end
fprintf('  %-46s V_dc: %6.3f %%    I_load: %6.3f %%\n\n', ...
        'TOTAL (all AC content)', rippleVdc, rippleIload);

%% ---- 6. Low-pass filter the DC signals (remove ripple/noise) ----
% filtfilt() applies the filter forward and backward, giving zero phase
% distortion (no time shift). That keeps the filtered trace correctly
% aligned in time with the raw trace, which matters for a fair
% raw-vs-filtered comparison on a DC signal.
Wn = cutoffFreq / (Fs / 2);    % normalized cutoff (0 < Wn < 1), Fs from Section 5

if Wn <= 0 || Wn >= 1
    error(['cutoffFreq = %.1f Hz is not valid for the detected sample rate ' ...
           '(%.1f Hz, Nyquist = %.1f Hz). Choose a cutoffFreq between 0 and ' ...
           '%.1f Hz.'], cutoffFreq, Fs, Fs/2, Fs/2);
end

[b, a] = butter(filterOrder, Wn, 'low');

Vdc_filt   = filtfilt(b, a, Vdc);
Iload_filt = filtfilt(b, a, Iload);

fprintf(['Sample rate detected: %.1f Hz. Low-pass filter: order %d Butterworth, ' ...
         'cutoff %d Hz, zero-phase (filtfilt).\n'], Fs, filterOrder, cutoffFreq);

%% ---- 7. Plot raw vs. filtered signals as two stacked subplots ----
figure('Name', 'DC Link Voltage & Load Current', 'Color', 'w');

% --- Top subplot: DC link voltage ---
ax1 = subplot(2, 1, 1);
plot(time, Vdc, 'Color', [0.65 0.65 1], 'LineWidth', 0.8); hold on;
plot(time, Vdc_filt, 'b-', 'LineWidth', 1.6);
hold off;
ylabel({'DC Link Voltage', 'V_{dc} (V)   [\times 10 scale]'});
title('DC Link Voltage  (CH1 raw reading \times 10)');
legend({sprintf('Unfiltered  (Ripple = %.2f%%)', rippleVdc), ...
        sprintf('Filtered (%d Hz LPF)', cutoffFreq)}, 'Location', 'best');
grid on;

% Highlight the x10 scaling directly on the voltage plot so it can't be
% missed when reading the y-axis
xl = xlim(ax1); yl = ylim(ax1);
xspan = xl(2) - xl(1);
yspan = yl(2) - yl(1);
text(xl(1) + 0.02*xspan, yl(2) - 0.06*yspan, ...
     'Scale \times 10 applied to raw CH1 reading', ...
     'FontWeight', 'bold', 'FontSize', 9, 'Color', [0.6 0 0], ...
     'BackgroundColor', [1 1 0.8], 'EdgeColor', 'k', ...
     'VerticalAlignment', 'top');

% --- Bottom subplot: load current ---
ax2 = subplot(2, 1, 2);
plot(time, Iload, 'Color', [1 0.65 0.65], 'LineWidth', 0.8); hold on;
plot(time, Iload_filt, 'r-', 'LineWidth', 1.6);
hold off;
xlabel('Time (s)');
ylabel('Load Current, I_{load} (A)');
title('Load Current  (CH2, no scaling)');
legend({sprintf('Unfiltered  (Ripple = %.2f%%)', rippleIload), ...
        sprintf('Filtered (%d Hz LPF)', cutoffFreq)}, 'Location', 'best');
grid on;

linkaxes([ax1, ax2], 'x');   % keep both time axes synced when zooming/panning
sgtitle('DC Link Voltage and Load Current: Raw vs. Low-Pass Filtered');

fprintf('Done. Plotted %d samples spanning %.4f s to %.4f s.\n', ...
        numel(time), time(1), time(end));

%% ---- 8. Plot the FFT spectra of Vdc and Iload (separate figure) ----
% Raw (unfiltered) data only, for the same reason noted in Section 5:
% this figure exists specifically to inspect ripple/harmonic content,
% and the low-pass filter above would hide exactly that.
figure('Name', 'Vdc & Iload FFT Spectra', 'Color', 'w');

xUpper = min(nyquist, max(switchFreq, 6*lineFreq) * 1.5);   % focus on the meaningful range
xLower = max(freqRes, 1);                                    % log axis can't start at 0

% --- Top subplot: Vdc spectrum ---
axf1 = subplot(2, 1, 1);
plot(axf1, freqVdc, specVdc, 'b-', 'LineWidth', 1);
set(axf1, 'XScale', 'log');
xlim(axf1, [xLower, xUpper]);
xlabel('Frequency (Hz)');
ylabel('Amplitude (V)');
title('V_{dc} FFT Spectrum (raw data)');
grid on; grid minor;
hold(axf1, 'on');
for k = 1:numel(compFreqs)
    if compFreqs(k) == 2*lineFreq
        xline(axf1, compFreqs(k), '--', compLabels{k}, 'Color', [0.85 0 0], ...
              'LineWidth', 1.8, 'FontWeight', 'bold', 'FontSize', 8, ...
              'LabelVerticalAlignment', 'top', 'LabelOrientation', 'horizontal');
    else
        xline(axf1, compFreqs(k), ':', compLabels{k}, 'Color', [0.4 0.4 0.4], ...
              'LineWidth', 1, 'FontSize', 8, ...
              'LabelVerticalAlignment', 'top', 'LabelOrientation', 'horizontal');
    end
end
hold(axf1, 'off');

% --- Bottom subplot: Iload spectrum ---
axf2 = subplot(2, 1, 2);
plot(axf2, freqIload, specIload, 'r-', 'LineWidth', 1);
set(axf2, 'XScale', 'log');
xlim(axf2, [xLower, xUpper]);
xlabel('Frequency (Hz)');
ylabel('Amplitude (A)');
title('I_{load} FFT Spectrum (raw data)');
grid on; grid minor;
hold(axf2, 'on');
for k = 1:numel(compFreqs)
    if compFreqs(k) == 2*lineFreq
        xline(axf2, compFreqs(k), '--', compLabels{k}, 'Color', [0.85 0 0], ...
              'LineWidth', 1.8, 'FontWeight', 'bold', 'FontSize', 8, ...
              'LabelVerticalAlignment', 'top', 'LabelOrientation', 'horizontal');
    else
        xline(axf2, compFreqs(k), ':', compLabels{k}, 'Color', [0.4 0.4 0.4], ...
              'LineWidth', 1, 'FontSize', 8, ...
              'LabelVerticalAlignment', 'top', 'LabelOrientation', 'horizontal');
    end
end
hold(axf2, 'off');

linkaxes([axf1, axf2], 'x');
sgtitle('Ripple / Harmonic Content — FFT of Raw V_{dc} and I_{load}');

idx100 = find(compFreqs == 2*lineFreq, 1);
if ~isempty(idx100)
    fprintf('FFT figure plotted. 100 Hz component: V_dc = %.3f%%, I_load = %.3f%% of DC mean.\n', ...
            pctVdc(idx100), pctIload(idx100));
else
    fprintf('FFT figure plotted. (100 Hz is above this capture''s Nyquist limit -- not resolvable.)\n');
end

%% ========================================================================
%  Local functions
%  ========================================================================
function [freqs, amp] = singleSidedSpectrum(x, Fs)
% Returns the single-sided, Hann-windowed, window-corrected amplitude
% spectrum of x. x is mean-removed before windowing, so this spectrum
% covers AC content only -- the DC/mean value is handled separately by
% the caller (mean() is a more direct and accurate estimate of it than
% reading the windowed FFT's DC bin would be).
    x = x(:) - mean(x(:));
    N = length(x);
    w = hann(N, 'periodic');
    xw = x .* w;

    Xf = fft(xw);
    halfN = floor(N/2) + 1;
    amp = (2 / sum(w)) * abs(Xf(1:halfN));   % window-corrected amplitude

    freqRes = Fs / N;
    freqs = (0:halfN-1) * freqRes;
end

function amp = peakNear(freqs, spec, fTarget, tolHz)
% Returns the peak spectral amplitude within +/- tolHz of fTarget, to
% tolerate limited frequency resolution and slight deviations from the
% nominal target frequency (e.g. line frequency not exactly 50.000 Hz).
    idxRange = find(freqs >= fTarget - tolHz & freqs <= fTarget + tolHz);
    if isempty(idxRange)
        [~, idxRange] = min(abs(freqs - fTarget));
    end
    amp = max(spec(idxRange));
end

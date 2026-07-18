%% ========================================================================
%  Plot Grid Voltage & Current Signals
%  ========================================================================
%  - Voltage CSV : 3-ch voltage   @ 100 kSa/s  (Rigol oscilloscope)
%  - Current CSV : 3-ch current   @  50 MSa/s   (Data acquisition unit)
%
%  The script decimates the high-rate current data to match the voltage
%  sampling rate so both can be overlaid on one coherent time axis.
%  ========================================================================
clc; clear; close all;

%% ========================================================================
%  1.  SELECT FILES VIA DIALOG
%  ========================================================================
% --- Select voltage CSV ---
[vFile, vPath] = uigetfile('*.csv', 'Select the VOLTAGE CSV file (Rigol)');
if isequal(vFile, 0)
    error('No voltage file selected. Aborting.');
end
fprintf('Voltage file: %s\n', fullfile(vPath, vFile));

% --- Select current CSV ---
[iFile, iPath] = uigetfile('*.csv', 'Select the CURRENT CSV file (UNIT)', vPath);
if isequal(iFile, 0)
    error('No current file selected. Aborting.');
end
fprintf('Current file: %s\n\n', fullfile(iPath, iFile));

%% ========================================================================
%  2.  LOAD VOLTAGE DATA
%  ========================================================================
fprintf('Loading voltage data ...\n');

% --- Parse header to extract t0 and tInc ---
fid = fopen(fullfile(vPath, vFile), 'r');
headerLine = fgetl(fid);
fclose(fid);

% Header format: "CH1V,CH2V,CH3V,t0 =-5.000000e-02, tInc = 1.000000e-05,"
tokens = regexp(headerLine, 't0\s*=\s*([\-\+\d\.eE]+)', 'tokens');
t0_v = str2double(tokens{1}{1});

tokens = regexp(headerLine, 'tInc\s*=\s*([\-\+\d\.eE]+)', 'tokens');
tInc_v = str2double(tokens{1}{1});

% --- Read the 3 voltage channels ---
% readmatrix handles trailing commas/empty columns gracefully
V = readmatrix(fullfile(vPath, vFile), 'NumHeaderLines', 1);
V = V(:, 1:3);   % keep only CH1V, CH2V, CH3V (discard NaN columns)

Nv = size(V, 1);
t_v = t0_v + (0:Nv-1).' * tInc_v;  % time vector [s]

fprintf('  Samples  : %d\n', Nv);
fprintf('  V_CH1    : [%.1f, %.1f] V\n', min(V(:,1)), max(V(:,1)));
fprintf('  Fs       : %.0f kSa/s\n', 1/tInc_v / 1e3);
fprintf('  Duration : %.3f ms\n', (Nv-1)*tInc_v*1e3);
fprintf('  Time     : [%.3f, %.3f] ms\n\n', t_v(1)*1e3, t_v(end)*1e3);

%% ========================================================================
%  3.  LOAD CURRENT DATA
%  ========================================================================
fprintf('Loading current data -- this may take a moment ...\n');

% --- Parse 11-line metadata header ---
fid = fopen(fullfile(iPath, iFile), 'r');
metaLines = cell(11, 1);
for k = 1:11
    metaLines{k} = fgetl(fid);
end
fclose(fid);

% Sampling Rate (line 3): "Sampling Rate:50MSa/s,"
tokens = regexp(metaLines{3}, 'Sampling Rate:(\d+)MSa/s', 'tokens');
Fs_c = str2double(tokens{1}{1}) * 1e6;      % Hz
tInc_c = 1 / Fs_c;                           % s

% Time Start (line 5): "Time Start:-70000000000ps,..."
tokens = regexp(metaLines{5}, 'Time Start:([\-\d]+)ps', 'tokens');
t0_c = str2double(tokens{1}{1}) * 1e-12;     % convert ps -> s

% Data points (line 10): "Data points:7000000,..."
tokens = regexp(metaLines{10}, 'Data points:(\d+)', 'tokens');
Nc_expected = str2double(tokens{1}{1});

% --- Read the 3 current channels (skip 11 header lines) ---
I_raw = readmatrix(fullfile(iPath, iFile), 'NumHeaderLines', 11);
I_raw = I_raw(:, 1:3);              % keep first 3 columns
I_raw = I_raw / 1000;               % convert mA -> A

Nc = size(I_raw, 1);
t_c = t0_c + (0:Nc-1).' * tInc_c;   % time vector [s]

fprintf('  Samples  : %d\n', Nc);
fprintf('  I_CH1    : [%.2f, %.2f] A\n', min(I_raw(:,1)), max(I_raw(:,1)));
fprintf('  Fs       : %.0f MSa/s\n', Fs_c/1e6);
fprintf('  Duration : %.3f ms\n', (Nc-1)*tInc_c*1e3);
fprintf('  Time     : [%.3f, %.3f] ms\n\n', t_c(1)*1e3, t_c(end)*1e3);

%% ========================================================================
%  4.  ADAPT SAMPLING RATES  (decimate current to match voltage)
%  ========================================================================
%  Voltage Fs = 100 kSa/s,  Current Fs = 50 MSa/s
%  Decimation factor = 50e6 / 100e3 = 500
%  decimate() applies an anti-aliasing filter before downsampling.
%  The decimation factor is computed automatically from the sampling rates.
%  For large factors, multi-stage decimation is used (each stage <= 13).
%  ------------------------------------------------------------------------
decimFactor = round(Fs_c * tInc_v);
fprintf('Decimating current data by factor %d ...\n', decimFactor);

% Factorize decimFactor into stages <= 13 for decimate() stability
stages = [];
remaining = decimFactor;
for p = [13 11 10 9 8 7 6 5 4 3 2]
    while mod(remaining, p) == 0
        stages(end+1) = p; %#ok<AGROW>
        remaining = remaining / p;
    end
end
if remaining > 1
    stages(end+1) = remaining; %#ok<AGROW>
end
fprintf('  Decimation stages: %s\n', mat2str(stages));

I_dec = [];
for ch = 1:3
    tmp = double(I_raw(:, ch));
    for s = 1:length(stages)
        tmp = decimate(tmp, stages(s));
    end
    if isempty(I_dec)
        I_dec = zeros(length(tmp), 3);
    end
    I_dec(1:length(tmp), ch) = tmp;
end
I_dec = I_dec(1:length(tmp), :);

Nc_dec = size(I_dec, 1);
tInc_c_dec = tInc_c * decimFactor;
t_c_dec = t0_c + (0:Nc_dec-1).' * tInc_c_dec;

fprintf('  Decimated samples : %d\n', Nc_dec);
fprintf('  New Fs            : %.2f MSa/s  (matches voltage)\n\n', 1/tInc_c_dec/1e6);

%% ========================================================================
%  5.  LOW-PASS FILTER ALL SIGNALS (clean Vabc & Iabc)
%  ========================================================================
%  Vabc/Iabc are 50 Hz grid quantities, not DC, so the cutoff can't sit
%  where it did for the earlier DC-link script (200 Hz is too close to
%  the fundamental and would attenuate/distort it). It needs to sit
%  comfortably above the fundamental -- and above whichever low-order
%  harmonics you want to keep -- while still being low enough to
%  meaningfully reject high-frequency measurement noise / switching
%  artifacts riding on top. 2 kHz = 40x the 50 Hz fundamental, so it
%  passes the fundamental and roughly the first ~40 harmonics
%  essentially undistorted while cutting noise above that. Raise it if
%  you need higher harmonics preserved (e.g. for THD-style analysis),
%  lower it if the signals still look noisy.
%
%  filtfilt() is used for zero-phase filtering. That matters even more
%  here than for a DC signal: any phase shift between the filtered V
%  and I would corrupt the voltage-current phase relationship (power
%  factor / phase angle), not just shift a trend line in time.
fundamentalFreq = 50;      % Hz - grid fundamental
filterOrder     = 2;       % 2nd-order Butterworth
cutoffFreq      = 2000;    % Hz - tune based on harmonics of interest vs. noise

fprintf('Filtering all 6 signals (order-%d Butterworth, %d Hz cutoff, zero-phase)...\n', ...
        filterOrder, cutoffFreq);

try
    butter(1, 0.1, 'low'); %#ok<NASGU>
catch ME
    error(['Failed to design the Butterworth filter - this usually means the ' ...
           'Signal Processing Toolbox is not installed. Original error: %s'], ...
           ME.message);
end

% --- Voltage filter (uses the voltage sampling rate) ---
Fs_v_actual = 1 / tInc_v;
Wn_v = cutoffFreq / (Fs_v_actual / 2);
if Wn_v <= 0 || Wn_v >= 1
    error(['cutoffFreq = %.1f Hz is not valid for the voltage sample rate ' ...
           '(%.1f Hz, Nyquist = %.1f Hz).'], cutoffFreq, Fs_v_actual, Fs_v_actual/2);
end
[bV, aV] = butter(filterOrder, Wn_v, 'low');

V_filt = zeros(size(V));
for ch = 1:3
    V_filt(:, ch) = filtfilt(bV, aV, V(:, ch));
end

% --- Current filter (uses the decimated current sampling rate) ---
Fs_i_actual = 1 / tInc_c_dec;
Wn_i = cutoffFreq / (Fs_i_actual / 2);
if Wn_i <= 0 || Wn_i >= 1
    error(['cutoffFreq = %.1f Hz is not valid for the decimated current sample ' ...
           'rate (%.1f Hz, Nyquist = %.1f Hz).'], cutoffFreq, Fs_i_actual, Fs_i_actual/2);
end
[bI, aI] = butter(filterOrder, Wn_i, 'low');

I_filt = zeros(size(I_dec));
for ch = 1:3
    I_filt(:, ch) = filtfilt(bI, aI, I_dec(:, ch));
end

fprintf('  Voltage Fs : %.1f kHz -> cutoff %d Hz (%.0fx fundamental)\n', ...
        Fs_v_actual/1e3, cutoffFreq, cutoffFreq/fundamentalFreq);
fprintf('  Current Fs : %.1f kHz -> cutoff %d Hz (%.0fx fundamental)\n\n', ...
        Fs_i_actual/1e3, cutoffFreq, cutoffFreq/fundamentalFreq);

%% ========================================================================
%  6.  CALCULATE THD FOR EACH CURRENT PHASE (Ia, Ib, Ic)
%  ========================================================================
%  THD is computed from the RAW (unfiltered) current data via FFT, not
%  from the low-pass-filtered signal above. A 2nd-order Butterworth
%  starts rolling off well before its cutoff, which would shave down
%  exactly the higher-order harmonics THD is meant to measure and
%  understate the result -- so harmonic content is measured directly
%  from what was actually captured, independent of the display filter.
%
%  Amplitudes come from a Hann-windowed FFT (reduces spectral leakage
%  from a non-integer number of captured cycles), searching a small
%  tolerance band around each expected harmonic frequency in case the
%  true grid frequency isn't exactly 50.000 Hz. THD sums harmonics 2
%  through thdMaxHarmonic -- matched to the filter's ~40th-harmonic
%  passband above so the two analyses stay consistent with each other.
thdMaxHarmonic = 40;

thdIa = computeTHD(I_dec(:,1), Fs_i_actual, fundamentalFreq, thdMaxHarmonic);
thdIb = computeTHD(I_dec(:,2), Fs_i_actual, fundamentalFreq, thdMaxHarmonic);
thdIc = computeTHD(I_dec(:,3), Fs_i_actual, fundamentalFreq, thdMaxHarmonic);

fprintf('THD (harmonics 2-%d, %.0f Hz fundamental):\n', thdMaxHarmonic, fundamentalFreq);
fprintf('  I_a : %.2f %%\n', thdIa);
fprintf('  I_b : %.2f %%\n', thdIb);
fprintf('  I_c : %.2f %%\n\n', thdIc);

%% ========================================================================
%  7.  CALCULATE TOTAL POWER FACTOR (Vabc & Iabc, raw)
%  ========================================================================
%  True power factor (real power / apparent power), from the RAW,
%  time-aligned V and I -- deliberate, so PF reflects the actual
%  measured power flow including any distortion rather than an
%  idealized cleaned-up waveform. Voltage and current were captured on
%  different instruments with different trigger points, so they don't
%  share the same time samples; current is resampled onto the
%  voltage's time grid within their overlapping window first.
overlapMask = (t_v >= max(t_v(1), t_c_dec(1))) & (t_v <= min(t_v(end), t_c_dec(end)));
tCommon = t_v(overlapMask);

Va_c = V(overlapMask, 1);  Vb_c = V(overlapMask, 2);  Vc_c = V(overlapMask, 3);
Ia_c = interp1(t_c_dec, I_dec(:,1), tCommon, 'linear');
Ib_c = interp1(t_c_dec, I_dec(:,2), tCommon, 'linear');
Ic_c = interp1(t_c_dec, I_dec(:,3), tCommon, 'linear');

P_a = mean(Va_c .* Ia_c);   P_b = mean(Vb_c .* Ib_c);   P_c = mean(Vc_c .* Ic_c);
P_total = P_a + P_b + P_c;

Vrms_a = sqrt(mean(Va_c.^2));  Vrms_b = sqrt(mean(Vb_c.^2));  Vrms_c = sqrt(mean(Vc_c.^2));
Irms_a = sqrt(mean(Ia_c.^2));  Irms_b = sqrt(mean(Ib_c.^2));  Irms_c = sqrt(mean(Ic_c.^2));
S_total = Vrms_a*Irms_a + Vrms_b*Irms_b + Vrms_c*Irms_c;

PF_total = P_total / S_total;

fprintf('Total power factor:\n');
fprintf('  P_total = %.3f W   S_total = %.3f VA   PF = %.4f\n\n', P_total, S_total, PF_total);

%% ========================================================================
%  8.  PLOT ALL 6 SIGNALS: RAW (LIGHT) + FILTERED (BOLD) OVERLAID
%  ========================================================================
fprintf('Plotting ...\n');

% --- Define distinct colors for each signal ---
% IEEE-Transactions-style palette: voltages in a cool blue family,
% currents in a warm red/orange family. Each phase is a distinct shade
% within its family so V and I are told apart by hue group at a glance,
% and by shade within the group. All muted/desaturated (no pure
% RGB/CMY primaries) to match typical IEEE figure conventions and stay
% legible when reproduced in grayscale.

colVa = [0.93 0.69 0.13];  % voltage phase A - dark navy blue
colVb = [0.00 0.45 0.74];   % voltage phase B - medium blue
colVc = [0.64 0.08 0.18];   % voltage phase C - light/cyan blue

colIa = [0.00 0.65 0.13];   % current phase A - medium blue
colIb = [0.85 0.33 0.10];   % current phase B - orange-red
colIc = [0.545, 0, 0.545];   % current phase C - amber/gold

% Light tint of each base color for the unfiltered trace (same hue,
% blended toward white) so raw and filtered are visually paired by
% color while remaining easy to tell apart.
lightBlend = 0.60;                         % fraction blended toward white
lighten = @(c) c + (1 - c) * lightBlend;

colVa_u = lighten(colVa);
colVb_u = lighten(colVb);
colVc_u = lighten(colVc);
colIa_u = lighten(colIa);
colIb_u = lighten(colIb);
colIc_u = lighten(colIc);

% --- X-axis limits (overlap region) ---
xLims = [max(t_v(1), t_c_dec(1))*1e3,  min(t_v(end), t_c_dec(end))*1e3];

% --- Compute scaling factor to map current onto voltage range ---
% Based on the raw (unfiltered) data, since it's now also plotted and is
% typically the higher-amplitude of the two (filtering tends to shave
% off noise peaks) -- this keeps both raw and filtered traces in view.
V_max = max(abs(V(:)));
I_max = max(abs(I_dec(:)));
shrink = 0.6;                        % current peaks at 60% of voltage amplitude
scale = (V_max / I_max) * shrink;

fig = figure('Name', 'Grid Voltage & Current', ...
             'Color', 'w', ...
             'Units', 'normalized', ...
             'Position', [0.05 0.08 0.88 0.82]);

% ---- Single axes: all 6 signals ----
ax1 = axes('Parent', fig, 'Position', [0.08 0.12 0.78 0.80]);
hold(ax1, 'on');

% Unfiltered (light shade) drawn first, so the filtered trace layers
% on top of it -- same hue per signal, light = raw, bold = filtered.
plot(ax1, t_v*1e3, V(:,1), '-', 'Color', colVa_u, 'LineWidth', 0.8);
plot(ax1, t_v*1e3, V(:,2), '-', 'Color', colVb_u, 'LineWidth', 0.8);
plot(ax1, t_v*1e3, V(:,3), '-', 'Color', colVc_u, 'LineWidth', 0.8);
plot(ax1, t_c_dec*1e3, I_dec(:,1)*scale, '-', 'Color', colIa_u, 'LineWidth', 0.6);
plot(ax1, t_c_dec*1e3, I_dec(:,2)*scale, '-', 'Color', colIb_u, 'LineWidth', 0.6);
plot(ax1, t_c_dec*1e3, I_dec(:,3)*scale, '-', 'Color', colIc_u, 'LineWidth', 0.6);

% Filtered (bold shade) -- plotted in Volts / scaled Amps, on top of raw
hVa = plot(ax1, t_v*1e3, V_filt(:,1), '-', 'Color', colVa, 'LineWidth', 1.5);
hVb = plot(ax1, t_v*1e3, V_filt(:,2), '-', 'Color', colVb, 'LineWidth', 1.5);
hVc = plot(ax1, t_v*1e3, V_filt(:,3), '-', 'Color', colVc, 'LineWidth', 1.5);
hIa = plot(ax1, t_c_dec*1e3, I_filt(:,1)*scale, '-', 'Color', colIa, 'LineWidth', 1.2);
hIb = plot(ax1, t_c_dec*1e3, I_filt(:,2)*scale, '-', 'Color', colIb, 'LineWidth', 1.2);
hIc = plot(ax1, t_c_dec*1e3, I_filt(:,3)*scale, '-', 'Color', colIc, 'LineWidth', 1.2);

hold(ax1, 'off');

ylabel(ax1, 'Voltage  [V]', 'FontSize', 12, 'FontWeight', 'bold');
xlabel(ax1, 'Time  [ms]', 'FontSize', 12, 'FontWeight', 'bold');
title(ax1, 'Synchronized Grid Voltage and Current: Raw (light) vs. Filtered (bold)', 'FontSize', 14);
set(ax1, 'FontSize', 11, 'LineWidth', 0.6);
xlim(ax1, xLims);
grid(ax1, 'on');

% Note explaining the light/bold shading convention (kept separate from
% the main legend so the legend stays at 6 entries, not 12)
annotation(fig, 'textbox', [0.08 0.955 0.5 0.04], ...
           'String', 'Light shade = unfiltered raw data   |   Bold shade = 2nd-order Butterworth filtered', ...
           'EdgeColor', 'none', 'FontSize', 9, 'FontAngle', 'italic', ...
           'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle');

% ---- Right y-axis: label-only axes for Current scale ----
yLims_V = ylim(ax1);
yLims_I = yLims_V / scale;
ax2 = axes('Parent', fig, ...
           'Position', get(ax1, 'Position'), ...
           'YAxisLocation', 'right', ...
           'YLim', yLims_I, ...
           'Color', 'none', ...
           'XTick', [], ...
           'Box', 'off');
ylabel(ax2, 'Current  [A]', 'FontSize', 12, 'FontWeight', 'bold');
set(ax2, 'FontSize', 11, 'LineWidth', 0.6);

% ---- Legend ----
legend(ax1, [hVa hVb hVc hIa hIb hIc], ...
       {'V_{a} (CH1)', 'V_{b} (CH2)', 'V_{c} (CH3)', ...
        sprintf('I_{a} (CH1)  THD = %.1f%%', thdIa), ...
        sprintf('I_{b} (CH2)  THD = %.1f%%', thdIb), ...
        sprintf('I_{c} (CH4)  THD = %.1f%%', thdIc)}, ...
       'Location', 'northeast', 'FontSize', 10);

% ---- Power factor label: large and prominent, in the empty right margin ----
pfStr = sprintf('Total PF\n%.3f', PF_total);
annotation(fig, 'textbox', [0.865 0.42 0.12 0.14], ...
           'String', pfStr, ...
           'FontSize', 20, 'FontWeight', 'bold', ...
           'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
           'BackgroundColor', [1 1 0.85], 'EdgeColor', 'k', 'LineWidth', 1.5);

fprintf('Done.\n');

%% ========================================================================
%  Local functions
%  ========================================================================
function thdPct = computeTHD(x, Fs, f0, maxHarmonic)
% Returns the Total Harmonic Distortion (%) of x relative to its
% fundamental at f0, summing harmonics 2..maxHarmonic (capped at
% Nyquist). Uses a Hann-windowed FFT and searches a small frequency
% tolerance around each harmonic bin to tolerate slight deviations from
% the nominal fundamental frequency and limited frequency resolution.
    x = x(:) - mean(x(:));           % remove DC offset
    N = length(x);
    w = hann(N, 'periodic');
    xw = x .* w;

    Xf = fft(xw);
    halfN = floor(N/2) + 1;
    amp = (2 / sum(w)) * abs(Xf(1:halfN));   % single-sided, window-corrected

    freqRes = Fs / N;
    freqs = (0:halfN-1) * freqRes;

    maxHarmonic = min(maxHarmonic, floor((Fs/2) / f0));
    tolHz = max(3 * freqRes, 2);

    harmAmp = zeros(1, maxHarmonic);
    for h = 1:maxHarmonic
        fTarget = h * f0;
        idxRange = find(freqs >= fTarget - tolHz & freqs <= fTarget + tolHz);
        if isempty(idxRange)
            [~, idxRange] = min(abs(freqs - fTarget));
        end
        harmAmp(h) = max(amp(idxRange));
    end

    thdPct = 100 * sqrt(sum(harmAmp(2:end).^2)) / harmAmp(1);
end

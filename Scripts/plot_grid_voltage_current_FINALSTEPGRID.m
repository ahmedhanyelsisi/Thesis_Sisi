%% ========================================================================
%  Plot Grid Voltage & Current Signals
%  ========================================================================
%  - Voltage CSV : 3-ch voltage   @ 100 kSa/s  (Rigol oscilloscope)
%  - Current CSV : 3-ch current   @  50 MSa/s  (Data acquisition unit)
%
%  The script decimates the high-rate current data to match the voltage
%  sampling rate so both can be overlaid on one coherent time axis.
%
%  NEW FEATURE (Section 3b): The user is asked whether the CURRENT log
%  appears to be chronologically out of order (e.g. a circular/rolling
%  buffer wraparound in the DAQ export, where data belonging at the start
%  of the record shows up somewhere in the middle instead). If so, the
%  splice point is auto-detected from the single largest sample-to-sample
%  discontinuity in the raw current magnitude -- something a real
%  electrical transient cannot produce at 50 MSa/s, since even a fast
%  step still evolves over many samples. The user confirms/corrects the
%  detected time, and the raw current array is ROTATED (not trimmed) so
%  the true earliest sample becomes sample 1. Sample count and duration
%  are unchanged; everything downstream (decimation, filtering, the
%  overlap window, load-step detection, THD, PF) automatically inherits
%  the corrected order.
%
%  UPDATED FEATURE (Section 4a): The voltage and current records are each
%  re-zeroed so that sample 1 of BOTH files is defined as t = 0 (see
%  Sections 2 & 3) -- this synchronizes their start by construction,
%  instead of relying on the scope/DAQ-reported t0 values. The full-
%  record overview plot (Figure 1) then runs from t = 0 to the END OF
%  THE CURRENT LOG. If the voltage record happens to be shorter than the
%  current record, the window is clipped to the voltage record's end
%  instead (with a warning), since there is no voltage data beyond that
%  point to plot or analyse.
%
%  NEW FEATURE (Section 4b): The user is asked whether a load step
%  occurred during the test. If so, the step instant is auto-detected
%  from the current magnitude envelope, a zoomed figure is generated to
%  highlight the transient, and ALL metric calculations (THD, PF) are
%  restricted to a post-step steady-state window so they remain reliable.
%
%  UPDATED FEATURE (Section 2b): The user is asked whether the voltage
%  log needs re-ordering because the true start of the record (t = 0)
%  sits at a known offset INTO the file rather than at sample 1 -- the
%  same kind of issue the current log has in Section 3b. If so, the
%  voltage sample array is ROTATED (never trimmed -- every sample kept)
%  so the sample at the given offset becomes sample 1, with the earlier
%  samples wrapped to the end.
%  ========================================================================
clc; clear; close all;

%% ========================================================================
%  1.  SELECT FILES VIA DIALOG
%  ========================================================================
[vFile, vPath] = uigetfile('*.csv', 'Select the VOLTAGE CSV file (Rigol)');
if isequal(vFile, 0), error('No voltage file selected. Aborting.'); end
fprintf('Voltage file : %s\n', fullfile(vPath, vFile));

[iFile, iPath] = uigetfile('*.csv', 'Select the CURRENT CSV file (UNIT)', vPath);
if isequal(iFile, 0), error('No current file selected. Aborting.'); end
fprintf('Current file : %s\n\n', fullfile(iPath, iFile));

%% ========================================================================
%  2.  LOAD VOLTAGE DATA
%  ========================================================================
fprintf('Loading voltage data ...\n');

fid = fopen(fullfile(vPath, vFile), 'r');
headerLine = fgetl(fid);
fclose(fid);

tokens  = regexp(headerLine, 't0\s*=\s*([\-\+\d\.eE]+)', 'tokens');
t0_v    = str2double(tokens{1}{1});
tokens  = regexp(headerLine, 'tInc\s*=\s*([\-\+\d\.eE]+)', 'tokens');
tInc_v  = str2double(tokens{1}{1});

V    = readmatrix(fullfile(vPath, vFile), 'NumHeaderLines', 1);
V    = V(:, 1:3);
Nv   = size(V, 1);

% Zero-based time axis: sample 1 is defined as t = 0, regardless of the
% scope-reported t0. This lets the voltage and current records be
% synchronized on a common t = 0 start (see Section 4a) instead of
% trusting the two instruments' independently-reported start times.
t_v  = (0:Nv-1).' * tInc_v;

fprintf('  Samples  : %d\n',   Nv);
fprintf('  V_CH1    : [%.1f, %.1f] V\n', min(V(:,1)), max(V(:,1)));
fprintf('  Fs       : %.0f kSa/s\n', 1/tInc_v/1e3);
fprintf('  Duration : %.3f ms\n', (Nv-1)*tInc_v*1e3);
fprintf('  Time     : [%.3f, %.3f] ms  (re-zeroed; scope-reported t0 = %.4f ms)\n\n', ...
        t_v(1)*1e3, t_v(end)*1e3, t0_v*1e3);

%% ========================================================================
%  2b.  VOLTAGE LOG RE-ORDERING / OFFSET CORRECTION  (UPDATED)
%  ========================================================================
%  The voltage capture can have the same kind of issue as the current
%  log in Section 3b: the sample the scope reports as t0 is not actually
%  the true chronological start of the record -- the true start sits a
%  known offset INTO the file, with everything before it belonging at
%  the END of the timeline instead.
%
%  If the user knows this offset, the record is ROTATED the same way the
%  current log was: the sample at that offset becomes sample 1, and the
%  samples before it move to the end. No samples are dropped.
%  ========================================================================
offsetAnswer = questdlg( ...
    ['Does the VOLTAGE log need re-ordering', newline, ...
     '(the true start of the record sits at a known offset INTO the', newline, ...
     'file, the same way the current log needed to be rotated)?'], ...
    'Voltage Re-ordering', 'Yes', 'No', 'No');

timeOffset_ms = 0;

if strcmp(offsetAnswer, 'Yes')
    prompt   = {sprintf(['Enter the offset [ms] INTO the record where the TRUE start\n' ...
                          '(t = 0) actually is.\nCurrent scope-reported t0 = %.4f ms.\n\n' ...
                          'Everything from this offset onward moves to the front of the\n' ...
                          'record; everything before it moves to the end. No samples are\n' ...
                          'dropped -- this only re-orders them, the same way the current\n' ...
                          'log was corrected in Section 3b.'], t0_v*1e3)};
    dlgTitle = 'Voltage Re-ordering Offset';
    dims     = [1 62];
    defVal   = {'0.000'};
    userResp = inputdlg(prompt, dlgTitle, dims, defVal);

    if isempty(userResp) || isnan(str2double(userResp{1}))
        fprintf('  No valid offset entered -- proceeding without re-ordering.\n\n');
    else
        timeOffset_ms = str2double(userResp{1});
    end
end

if timeOffset_ms ~= 0
    nShift = round((timeOffset_ms/1e3) / tInc_v);
    nShift = max(0, min(Nv-1, nShift));   % clamp to a valid in-range rotation

    if nShift > 0
        V = [V(nShift+1:end, :); V(1:nShift, :)];
        fprintf('  Re-ordered voltage record: sample %d is now sample 1.\n', nShift+1);
        fprintf('  (%d samples moved from the start back to the end)\n\n', nShift);
    else
        fprintf('  Offset rounds to 0 samples -- no re-ordering applied.\n\n');
    end
else
    fprintf('Voltage re-ordering: none applied.\n\n');
end

%% ========================================================================
%  3.  LOAD CURRENT DATA
%  ========================================================================
fprintf('Loading current data -- this may take a moment ...\n');

fid = fopen(fullfile(iPath, iFile), 'r');
metaLines = cell(11, 1);
for k = 1:11, metaLines{k} = fgetl(fid); end
fclose(fid);

tokens = regexp(metaLines{3},  'Sampling Rate:(\d+)MSa/s',  'tokens');
Fs_c   = str2double(tokens{1}{1}) * 1e6;
tInc_c = 1 / Fs_c;

tokens = regexp(metaLines{5},  'Time Start:([\-\d]+)ps',    'tokens');
t0_c   = str2double(tokens{1}{1}) * 1e-12;

I_raw  = readmatrix(fullfile(iPath, iFile), 'NumHeaderLines', 11);
I_raw  = I_raw(:, 1:3) / 1000;   % mA -> A

Nc     = size(I_raw, 1);

% Zero-based time axis, same rationale as the voltage record above:
% sample 1 of the current record is defined as t = 0.
t_c    = (0:Nc-1).' * tInc_c;

fprintf('  Samples  : %d\n',   Nc);
fprintf('  I_CH1    : [%.2f, %.2f] A\n', min(I_raw(:,1)), max(I_raw(:,1)));
fprintf('  Fs       : %.0f MSa/s\n', Fs_c/1e6);
fprintf('  Duration : %.3f ms\n', (Nc-1)*tInc_c*1e3);
fprintf('  Time     : [%.3f, %.3f] ms  (re-zeroed; DAQ-reported t0 = %.4f ms)\n\n', ...
        t_c(1)*1e3, t_c(end)*1e3, t0_c*1e3);

%% ========================================================================
%  3b.  CURRENT LOG WRAPAROUND / RE-ORDERING CORRECTION  (NEW)
%  ========================================================================
%  Some current DAQ units export a continuously-running circular buffer
%  as a flat CSV, so the file is NOT guaranteed to start at the
%  chronologically earliest sample -- the true start can land partway
%  through the file, with the "tail" of the real timeline wrapped around
%  to the front of the export. If that has happened here, the record
%  needs to be ROTATED (never trimmed -- every sample is kept, none are
%  dropped) so the chronologically earliest sample becomes sample 1.
%
%  Detection: a genuine buffer-wrap splice shows up as one abrupt,
%  single-sample discontinuity that is far larger than anything a real
%  electrical transient could produce at this sample rate -- two
%  unrelated segments of the waveform stitched together with no
%  consistent phase or slope across the join. A real load step, however
%  fast, still evolves smoothly over many samples at 50 MSa/s. That
%  difference is what lets the splice be found automatically.
%  ========================================================================
wrapAnswer = questdlg( ...
    ['Does the CURRENT log appear to be chronologically out of order', newline, ...
     '(e.g. a buffer wraparound, where data that belongs at the start', newline, ...
     'of the record shows up somewhere in the middle instead)?'], ...
    'Current Log Re-ordering', 'Yes', 'No', 'No');

if strcmp(wrapAnswer, 'Yes')
    fprintf('Searching for a buffer-wrap splice in the current record ...\n');

    % Magnitude of the 3-phase current at full raw (pre-decimation) resolution
    I_mag_raw = sqrt(sum(I_raw.^2, 2));

    % Sample-to-sample jump size
    dMag = abs(diff(I_mag_raw));

    % Score each jump against a robust local baseline (median jump size).
    % A true splice stands far above this -- even the fastest genuine
    % transient does not produce a single-sample discontinuity this large.
    baseline    = median(dMag);
    splineScore = dMag / max(baseline, eps);

    [maxScore, splitIdx] = max(splineScore);
    splitIdx    = splitIdx + 1;                 % +1 for diff offset
    t_splice_ms = (splitIdx-1) * tInc_c * 1e3;  % zero-based numbering (matches t_c)

    fprintf('  Largest discontinuity at sample %d  (t = %.3f ms, zero-based numbering)\n', ...
            splitIdx, t_splice_ms);
    fprintf('  Jump size: %.1fx the typical sample-to-sample change\n', maxScore);

    prompt   = {sprintf(['Time [ms] to treat as the TRUE start of the record.\n' ...
                          'Auto-detected splice at t = %.4f ms (zero-based numbering).\n\n' ...
                          'Everything from this time onward moves to the front of the\n' ...
                          'record; everything before it moves to the end. No samples\n' ...
                          'are dropped -- this only re-orders them.'], t_splice_ms)};
    dlgTitle = 'Confirm / Correct Wrap Point';
    dims     = [1 62];
    defVal   = {sprintf('%.4f', t_splice_ms)};
    userResp = inputdlg(prompt, dlgTitle, dims, defVal);

    if isempty(userResp) || isnan(str2double(userResp{1}))
        fprintf('  No valid time entered -- proceeding without re-ordering.\n\n');
    else
        t_splice_ms = str2double(userResp{1});
        splitIdx    = round((t_splice_ms/1e3) / tInc_c) + 1;
        splitIdx    = max(1, min(Nc, splitIdx));

        if splitIdx == 1
            fprintf('  Splice point is already sample 1 -- no re-ordering needed.\n\n');
        else
            I_raw = [I_raw(splitIdx:end, :); I_raw(1:splitIdx-1, :)];
            fprintf('  Re-ordered current record: sample %d is now sample 1.\n', splitIdx);
            fprintf('  (%d samples moved from the end back to the start)\n\n', splitIdx-1);
        end
    end
else
    fprintf('Current log re-ordering: none applied.\n\n');
end

%% ========================================================================
%  4.  DECIMATE CURRENT TO MATCH VOLTAGE SAMPLING RATE
%  ========================================================================
decimFactor = round(Fs_c * tInc_v);
fprintf('Decimating current data by factor %d ...\n', decimFactor);

stages = factorizeDecimation(decimFactor);
fprintf('  Decimation stages: %s\n', mat2str(stages));

I_dec = [];
for ch = 1:3
    tmp = double(I_raw(:, ch));
    for s = 1:length(stages), tmp = decimate(tmp, stages(s)); end
    if isempty(I_dec), I_dec = zeros(length(tmp), 3); end
    I_dec(1:length(tmp), ch) = tmp;
end
I_dec = I_dec(1:length(tmp), :);

Nc_dec     = size(I_dec, 1);
tInc_c_dec = tInc_c * decimFactor;
t_c_dec    = (0:Nc_dec-1).' * tInc_c_dec;   % zero-based, consistent with t_c
Fs_i_dec   = 1 / tInc_c_dec;

fprintf('  Decimated samples : %d\n', Nc_dec);
fprintf('  New Fs            : %.2f kSa/s  (matches voltage)\n\n', Fs_i_dec/1e3);

%% ========================================================================
%  4a.  SYNCHRONIZE VOLTAGE & CURRENT AT t = 0, END AT CURRENT LOG END  (UPDATED)
%  ========================================================================
%  Both records are now zero-based (Sections 2 and 3: sample 1 of each
%  file is t = 0), so they are synchronized at the start by construction
%  -- no scope/DAQ t0 offset is involved any more.
%
%  The analysis/plot window runs from t = 0 to the END OF THE CURRENT
%  LOG, since the current record is the reference length. If the voltage
%  record happens to be shorter than the current record, the window is
%  clipped to the voltage record's end instead (there is no voltage data
%  beyond that point to plot or analyse), and a warning is printed.
%  ========================================================================
overlapStart = 0;
overlapEnd   = t_c_dec(end);   % end of current log, per spec

if t_v(end) < overlapEnd
    warning(['Voltage record (%.3f ms) is shorter than the current record ' ...
             '(%.3f ms). Clipping the analysis/plot window to the voltage ' ...
             'record end -- no voltage data exists beyond that point.'], ...
            t_v(end)*1e3, overlapEnd*1e3);
    overlapEnd = t_v(end);
end

if overlapEnd <= overlapStart
    error(['No usable synchronized data: the voltage or current record ' ...
           'has zero length. Check the CSV headers and decimation.']);
end

fprintf('Synchronized window (t = 0 at both records'' first sample):\n');
fprintf('  Voltage record  : [%.3f, %.3f] ms\n', t_v(1)*1e3, t_v(end)*1e3);
fprintf('  Current record  : [%.3f, %.3f] ms\n', t_c_dec(1)*1e3, t_c_dec(end)*1e3);
fprintf('  --> Plot window : [%.3f, %.3f] ms  (%.3f ms)\n\n', ...
        overlapStart*1e3, overlapEnd*1e3, (overlapEnd-overlapStart)*1e3);

%% ========================================================================
%  4b.  LOAD-STEP DETECTION  (NEW)
%  ========================================================================
%  Ask the user whether a load step happened during the capture.  If yes:
%    (a) Auto-detect the step instant from the current envelope derivative.
%    (b) Let the user tweak the detection if it looks wrong.
%    (c) Build a "steady-state analysis window" that starts a configurable
%        number of cycles AFTER the step so transient ringing is excluded.
%    (d) Generate a zoomed figure centred on the step.
%  All downstream metric calculations (THD, PF) use this SS window.
%  ========================================================================

% --- USER-TUNABLE STEP-DETECTION PARAMETERS ---
stepWin_ms         = 50;    % half-width [ms] of the zoomed plot around the step
settlingCycles     = 20;     % grid cycles to skip after the step before SS window
analysisEndMargin  = 0.05;  % fraction of record left after step excluded from SS end

hasLoadStep = false;
t_step_ms   = NaN;          % step time in ms (filled if user says yes)
t_ss_start  = NaN;          % SS analysis window start [s]
t_ss_end    = NaN;          % SS analysis window end   [s]

answer = questdlg( ...
    ['Did a load step occur during this test?', newline, ...
     'If YES the step instant will be auto-detected and metrics will be ', ...
     'calculated on the post-step steady-state portion only.'], ...
    'Load Step?', 'Yes', 'No', 'No');

if strcmp(answer, 'Yes')
    hasLoadStep = true;
    fprintf('Load-step mode: ON\n');

    % -----------------------------------------------------------------------
    % Auto-detect step from the magnitude of the current envelope derivative.
    % RMS energy computed in a short sliding window; derivative spike = step.
    % -----------------------------------------------------------------------
    envWin_samples = round(0.5e-3 / tInc_c_dec);   % 0.5 ms window
    if envWin_samples < 2, envWin_samples = 2; end

    % Use the three-phase current magnitude (Euclidean norm per sample)
    I_mag    = sqrt(sum(I_dec .^ 2, 2));

    % Moving-RMS envelope
    I_env    = movmean(I_mag .^ 2, envWin_samples);
    I_env    = sqrt(max(I_env, 0));

    % Derivative of envelope, normalised to peak
    dI_env   = abs(diff(I_env));
    dI_norm  = dI_env / max(dI_env);

    % First sample whose normalised derivative exceeds 30 % = step instant
    stepThresh = 0.30;
    stepIdx    = find(dI_norm > stepThresh, 1, 'first') + 1;  % +1 for diff offset

    if isempty(stepIdx)
        warning(['Auto-detection could not find a clear step (threshold %.0f%%). ' ...
                 'Falling back to interactive selection.'], stepThresh*100);
        stepIdx = round(Nc_dec / 2);
    end

    t_step_detected = t_c_dec(stepIdx);
    t_step_ms       = t_step_detected * 1e3;

    fprintf('  Auto-detected step @ t = %.3f ms (sample %d)\n', t_step_ms, stepIdx);

    % --- Let the user accept or manually correct the detection ---
    prompt   = {'Step time [ms] (edit if auto-detection is wrong):'};
    dlgTitle = 'Confirm / Correct Step Instant';
    dims     = [1 52];
    defVal   = {sprintf('%.4f', t_step_ms)};
    userResp = inputdlg(prompt, dlgTitle, dims, defVal);

    if isempty(userResp)
        fprintf('  User cancelled step confirmation. Disabling load-step mode.\n');
        hasLoadStep = false;
    else
        t_step_ms  = str2double(userResp{1});
        t_step_sec = t_step_ms / 1e3;
        fprintf('  Confirmed step time: %.4f ms\n', t_step_ms);

        % --- Build the steady-state analysis window ---
        f0           = 50;   % grid fundamental [Hz]
        settlingTime = settlingCycles / f0;     % [s] after step to skip

        t_ss_start = t_step_sec + settlingTime;

        % Compute SS end safely regardless of whether end time is negative.
        % Using multiplication by (1-margin) is wrong for negative timestamps
        % because it makes the value more negative instead of pulling it back.
        % Instead, subtract a fraction of the total record duration from the end.
        overlapEndTmp   = overlapEnd;
        overlapStartTmp = overlapStart;
        recordDuration  = overlapEndTmp - overlapStartTmp;
        t_ss_end = overlapEndTmp - recordDuration * analysisEndMargin;

        if t_ss_start >= t_ss_end
            warning(['The post-step settling window (%.0f cycles = %.1f ms) ' ...
                     'extends beyond the available data. Falling back to full ' ...
                     'signal for metrics.'], settlingCycles, settlingTime*1e3);
            hasLoadStep = false;
        else
            fprintf('  Steady-state window: [%.3f, %.3f] ms  (%.1f ms duration)\n\n', ...
                    t_ss_start*1e3, t_ss_end*1e3, (t_ss_end - t_ss_start)*1e3);
        end
    end
else
    fprintf('Load-step mode: OFF — metrics computed over full synchronized window.\n\n');
end

%% ========================================================================
%  5.  LOW-PASS FILTER ALL SIGNALS (zero-phase Butterworth)
%  ========================================================================
fundamentalFreq = 50;
filterOrder     = 2;
cutoffFreq      = 500;   % Hz

fprintf('Filtering all 6 signals (order-%d Butterworth, %d Hz cutoff, zero-phase)...\n', ...
        filterOrder, cutoffFreq);

Fs_v_actual = 1 / tInc_v;
Wn_v = cutoffFreq / (Fs_v_actual / 2);
if Wn_v <= 0 || Wn_v >= 1
    error('cutoffFreq = %.1f Hz is invalid for voltage Fs = %.1f Hz.', cutoffFreq, Fs_v_actual);
end
[bV, aV] = butter(filterOrder, Wn_v, 'low');

V_filt = zeros(size(V));
for ch = 1:3, V_filt(:, ch) = filtfilt(bV, aV, V(:, ch)); end

Wn_i = cutoffFreq / (Fs_i_dec / 2);
if Wn_i <= 0 || Wn_i >= 1
    error('cutoffFreq = %.1f Hz is invalid for decimated current Fs = %.1f Hz.', cutoffFreq, Fs_i_dec);
end
[bI, aI] = butter(filterOrder, Wn_i, 'low');

I_filt = zeros(size(I_dec));
for ch = 1:3, I_filt(:, ch) = filtfilt(bI, aI, I_dec(:, ch)); end

fprintf('  Voltage Fs : %.1f kHz -> cutoff %d Hz (%.0fx fundamental)\n', ...
        Fs_v_actual/1e3, cutoffFreq, cutoffFreq/fundamentalFreq);
fprintf('  Current Fs : %.1f kHz -> cutoff %d Hz (%.0fx fundamental)\n\n', ...
        Fs_i_dec/1e3, cutoffFreq, cutoffFreq/fundamentalFreq);

%% ========================================================================
%  6.  BUILD ANALYSIS WINDOW (full synchronized window OR post-step SS window)
%  ========================================================================
%  Create a common time mask shared by BOTH instruments.  When a load step
%  is confirmed the mask is further restricted to the post-step SS window.
%  overlapStart/overlapEnd were already set in Section 4a.
%  ========================================================================
if hasLoadStep
    analysisStart = max(overlapStart, t_ss_start);
    analysisEnd   = min(overlapEnd,   t_ss_end);
    windowLabel   = sprintf('Post-step SS window (%.0f cycles after step)', settlingCycles);
else
    analysisStart = overlapStart;
    analysisEnd   = overlapEnd;
    windowLabel   = 'Full synchronized window';
end

fprintf('Analysis window [%s]:\n', windowLabel);
fprintf('  Start : %.3f ms\n', analysisStart*1e3);
fprintf('  End   : %.3f ms\n', analysisEnd*1e3);
fprintf('  Length: %.3f ms\n\n', (analysisEnd - analysisStart)*1e3);

% --- Masks for voltage and current arrays ---
vMask = (t_v     >= analysisStart) & (t_v     <= analysisEnd);
iMask = (t_c_dec >= analysisStart) & (t_c_dec <= analysisEnd);

% Current decimated to analysis window (for THD FFT input)
I_dec_ss  = I_dec(iMask, :);
Fs_i_ss   = Fs_i_dec;          % same sampling rate — mask just clips the vector

%% ========================================================================
%  7.  THD (computed from post-step SS decimated current, if applicable)
%  ========================================================================
thdMaxHarmonic = 40;

thdIa = computeTHD(I_dec_ss(:,1), Fs_i_ss, fundamentalFreq, thdMaxHarmonic);
thdIb = computeTHD(I_dec_ss(:,2), Fs_i_ss, fundamentalFreq, thdMaxHarmonic);
thdIc = computeTHD(I_dec_ss(:,3), Fs_i_ss, fundamentalFreq, thdMaxHarmonic);

fprintf('THD (%s, harmonics 2-%d):\n', windowLabel, thdMaxHarmonic);
fprintf('  I_a : %.2f %%\n', thdIa);
fprintf('  I_b : %.2f %%\n', thdIb);
fprintf('  I_c : %.2f %%\n\n', thdIc);

%% ========================================================================
%  8.  POWER FACTOR (computed from post-step SS window, if applicable)
%  ========================================================================
tCommon = t_v(vMask);

Va_c = V(vMask, 1);  Vb_c = V(vMask, 2);  Vc_c = V(vMask, 3);
Ia_c = interp1(t_c_dec, I_dec(:,1), tCommon, 'linear');
Ib_c = interp1(t_c_dec, I_dec(:,2), tCommon, 'linear');
Ic_c = interp1(t_c_dec, I_dec(:,3), tCommon, 'linear');

P_a = mean(Va_c .* Ia_c);
P_b = mean(Vb_c .* Ib_c);
P_c = mean(Vc_c .* Ic_c);
P_total = P_a + P_b + P_c;

Vrms_a = sqrt(mean(Va_c.^2));  Vrms_b = sqrt(mean(Vb_c.^2));  Vrms_c = sqrt(mean(Vc_c.^2));
Irms_a = sqrt(mean(Ia_c.^2));  Irms_b = sqrt(mean(Ib_c.^2));  Irms_c = sqrt(mean(Ic_c.^2));
S_total = Vrms_a*Irms_a + Vrms_b*Irms_b + Vrms_c*Irms_c;

PF_total = P_total / S_total;

fprintf('Total power factor [%s]:\n', windowLabel);
fprintf('  P = %.3f W   |   S = %.3f VA   |   PF = %.4f\n\n', P_total, S_total, PF_total);

%% ========================================================================
%  9.  COLOURS
%  ========================================================================
colVa = [0.93 0.69 0.13];
colVb = [0.00 0.45 0.74];
colVc = [0.64 0.08 0.18];
colIa = [0.00 0.65 0.13];
colIb = [0.85 0.33 0.10];
colIc = [0.545 0.00 0.545];

lightBlend = 0.60;
lighten    = @(c) c + (1 - c) * lightBlend;

colVa_u = lighten(colVa);  colVb_u = lighten(colVb);  colVc_u = lighten(colVc);
colIa_u = lighten(colIa);  colIb_u = lighten(colIb);  colIc_u = lighten(colIc);

V_max  = max(abs(V(:)));
I_max  = max(abs(I_dec(:)));
shrink = 0.6;
scale  = (V_max / I_max) * shrink;

%% ========================================================================
%  10.  FIGURE 1: FULL-RECORD OVERVIEW (t = 0 to end of current log)
%  ========================================================================
fprintf('Plotting full-record overview ...\n');

% The x-axis (and the plotted data itself) is now clipped to the
% synchronized window computed in Section 4a: t = 0 (common start of
% both records) through the end of the current log -- or the voltage
% log's end, if the voltage record is the shorter of the two.
xLims_full = [overlapStart, overlapEnd] * 1e3;

vMaskFull = (t_v     >= overlapStart) & (t_v     <= overlapEnd);
iMaskFull = (t_c_dec >= overlapStart) & (t_c_dec <= overlapEnd);

t_v_plot    = t_v(vMaskFull);
V_plot      = V(vMaskFull, :);
V_filt_plot = V_filt(vMaskFull, :);

t_c_plot    = t_c_dec(iMaskFull);
I_plot      = I_dec(iMaskFull, :);
I_filt_plot = I_filt(iMaskFull, :);

fig1 = figure('Name', 'Grid Signals — Full Record', ...
              'Color', 'w', 'Units', 'normalized', 'Position', [0.03 0.08 0.88 0.82]);

ax1 = axes('Parent', fig1, 'Position', [0.08 0.12 0.78 0.80]);
hold(ax1, 'on');

plot(ax1, t_v_plot*1e3, V_plot(:,1), '-', 'Color', colVa_u, 'LineWidth', 0.8);
plot(ax1, t_v_plot*1e3, V_plot(:,2), '-', 'Color', colVb_u, 'LineWidth', 0.8);
plot(ax1, t_v_plot*1e3, V_plot(:,3), '-', 'Color', colVc_u, 'LineWidth', 0.8);
plot(ax1, t_c_plot*1e3, I_plot(:,1)*scale, '-', 'Color', colIa_u, 'LineWidth', 0.6);
plot(ax1, t_c_plot*1e3, I_plot(:,2)*scale, '-', 'Color', colIb_u, 'LineWidth', 0.6);
plot(ax1, t_c_plot*1e3, I_plot(:,3)*scale, '-', 'Color', colIc_u, 'LineWidth', 0.6);

hVa = plot(ax1, t_v_plot*1e3, V_filt_plot(:,1), '-', 'Color', colVa, 'LineWidth', 1.5);
hVb = plot(ax1, t_v_plot*1e3, V_filt_plot(:,2), '-', 'Color', colVb, 'LineWidth', 1.5);
hVc = plot(ax1, t_v_plot*1e3, V_filt_plot(:,3), '-', 'Color', colVc, 'LineWidth', 1.5);
hIa = plot(ax1, t_c_plot*1e3, I_filt_plot(:,1)*scale, '-', 'Color', colIa, 'LineWidth', 1.2);
hIb = plot(ax1, t_c_plot*1e3, I_filt_plot(:,2)*scale, '-', 'Color', colIb, 'LineWidth', 1.2);
hIc = plot(ax1, t_c_plot*1e3, I_filt_plot(:,3)*scale, '-', 'Color', colIc, 'LineWidth', 1.2);

% ---- Annotate load step and analysis window on the full-record plot ----
if hasLoadStep
    % Vertical dashed red line at the detected step instant
    yRange = ylim(ax1);
    plot(ax1, [t_step_ms t_step_ms], yRange, 'r--', 'LineWidth', 2.0);
    text(ax1, t_step_ms, yRange(2)*0.92, ...
         sprintf('  Step\n  t = %.2f ms', t_step_ms), ...
         'Color', 'r', 'FontSize', 10, 'FontWeight', 'bold', ...
         'VerticalAlignment', 'top');

    % Shaded rectangle = discarded settling region (step -> SS start)
    settling_x = [t_step_ms, t_ss_start*1e3, t_ss_start*1e3, t_step_ms];
    settling_y = [yRange(1), yRange(1), yRange(2), yRange(2)];
    fill(ax1, settling_x, settling_y, [1 0.8 0.8], ...
         'FaceAlpha', 0.25, 'EdgeColor', 'none');
    text(ax1, (t_step_ms + t_ss_start*1e3)/2, yRange(2)*0.70, ...
         sprintf('Settling\n(%.0f cyc)', settlingCycles), ...
         'Color', [0.7 0.1 0.1], 'FontSize', 8.5, 'FontAngle', 'italic', ...
         'HorizontalAlignment', 'center');

    % Shaded rectangle = SS analysis window
    ss_x = [t_ss_start*1e3, t_ss_end*1e3, t_ss_end*1e3, t_ss_start*1e3];
    ss_y = [yRange(1), yRange(1), yRange(2), yRange(2)];
    fill(ax1, ss_x, ss_y, [0.8 1 0.8], ...
         'FaceAlpha', 0.25, 'EdgeColor', 'none');
    text(ax1, (t_ss_start*1e3 + t_ss_end*1e3)/2, yRange(2)*0.70, ...
         sprintf('SS Analysis Window\n(THD & PF computed here)'), ...
         'Color', [0.05 0.5 0.05], 'FontSize', 8.5, 'FontAngle', 'italic', ...
         'HorizontalAlignment', 'center');
end

hold(ax1, 'off');

titleStr = 'Synchronized Grid Voltage & Current (t=0 to end of current log): Raw (light) vs. Filtered (bold)';
if hasLoadStep
    titleStr = [titleStr, sprintf(' — Load Step @ %.2f ms', t_step_ms)];
end
title(ax1, titleStr, 'FontSize', 13, 'FontWeight', 'bold');
ylabel(ax1, 'Voltage  [V]', 'FontSize', 12, 'FontWeight', 'bold');
xlabel(ax1, 'Time  [ms]',   'FontSize', 12, 'FontWeight', 'bold');
set(ax1, 'FontSize', 11, 'LineWidth', 0.6);
xlim(ax1, xLims_full);
grid(ax1, 'on');

annotation(fig1, 'textbox', [0.08 0.955 0.5 0.04], ...
    'String', 'Light shade = unfiltered raw data   |   Bold shade = 2nd-order Butterworth filtered', ...
    'EdgeColor', 'none', 'FontSize', 9, 'FontAngle', 'italic', ...
    'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle');

% Right axis (current scale)
yLims_V = ylim(ax1);
ax2 = axes('Parent', fig1, 'Position', get(ax1, 'Position'), ...
           'YAxisLocation', 'right', 'YLim', yLims_V/scale, ...
           'Color', 'none', 'XTick', [], 'Box', 'off');
ylabel(ax2, 'Current  [A]', 'FontSize', 12, 'FontWeight', 'bold');
set(ax2, 'FontSize', 11, 'LineWidth', 0.6);

legend(ax1, [hVa hVb hVc hIa hIb hIc], ...
       {'V_{a}', 'V_{b}', 'V_{c}', ...
        sprintf('I_{a}  THD = %.1f%%', thdIa), ...
        sprintf('I_{b}  THD = %.1f%%', thdIb), ...
        sprintf('I_{c}  THD = %.1f%%', thdIc)}, ...
       'Location', 'northeast', 'FontSize', 10);

% PF annotation box
pfLabel = sprintf('PF\n%.4f\n[%s]', PF_total, ...
                  strrep(windowLabel, ' window', ''));
annotation(fig1, 'textbox', [0.865 0.40 0.12 0.18], ...
    'String', pfLabel, ...
    'FontSize', 16, 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
    'BackgroundColor', [1 1 0.85], 'EdgeColor', 'k', 'LineWidth', 1.5);

%% ========================================================================
%  11.  FIGURE 2 (LOAD-STEP ONLY): ZOOMED PLOT CENTRED ON THE STEP
%  ========================================================================
if hasLoadStep
    fprintf('Plotting zoomed step view ...\n');

    xLims_zoom = [t_step_ms - stepWin_ms,  t_step_ms + stepWin_ms];
    % Clamp to available (synchronized) data
    xLims_zoom(1) = max(xLims_zoom(1), xLims_full(1));
    xLims_zoom(2) = min(xLims_zoom(2), xLims_full(2));

    fig2 = figure('Name', 'Load-Step Zoom', ...
                  'Color', 'w', 'Units', 'normalized', 'Position', [0.05 0.08 0.88 0.82]);

    % ---- Top sub-panel: Voltage ----
    ax_v = subplot(2,1,1);
    hold(ax_v, 'on');

    plot(ax_v, t_v_plot*1e3, V_plot(:,1), '-', 'Color', colVa_u, 'LineWidth', 0.8);
    plot(ax_v, t_v_plot*1e3, V_plot(:,2), '-', 'Color', colVb_u, 'LineWidth', 0.8);
    plot(ax_v, t_v_plot*1e3, V_plot(:,3), '-', 'Color', colVc_u, 'LineWidth', 0.8);

    hVa2 = plot(ax_v, t_v_plot*1e3, V_filt_plot(:,1), '-', 'Color', colVa, 'LineWidth', 2.0);
    hVb2 = plot(ax_v, t_v_plot*1e3, V_filt_plot(:,2), '-', 'Color', colVb, 'LineWidth', 2.0);
    hVc2 = plot(ax_v, t_v_plot*1e3, V_filt_plot(:,3), '-', 'Color', colVc, 'LineWidth', 2.0);

    yRv  = ylim(ax_v);
    plot(ax_v, [t_step_ms t_step_ms], yRv, 'r--', 'LineWidth', 2.0);

    % Settling shading
    fill(ax_v, [t_step_ms t_ss_start*1e3 t_ss_start*1e3 t_step_ms], ...
               [yRv(1) yRv(1) yRv(2) yRv(2)], ...
               [1 0.8 0.8], 'FaceAlpha', 0.30, 'EdgeColor', 'none');

    hold(ax_v, 'off');
    xlim(ax_v, xLims_zoom);
    ylabel(ax_v, 'Voltage  [V]',  'FontSize', 12, 'FontWeight', 'bold');
    title(ax_v, sprintf('Load-Step Zoom  ±%.0f ms around t = %.2f ms', stepWin_ms, t_step_ms), ...
          'FontSize', 13, 'FontWeight', 'bold');
    legend(ax_v, [hVa2 hVb2 hVc2], {'V_{a}','V_{b}','V_{c}'}, ...
           'Location','northwest', 'FontSize', 10);
    grid(ax_v, 'on');
    set(ax_v, 'FontSize', 11);

    % ---- Bottom sub-panel: Current ----
    ax_i = subplot(2,1,2);
    hold(ax_i, 'on');

    plot(ax_i, t_c_plot*1e3, I_plot(:,1), '-', 'Color', colIa_u, 'LineWidth', 0.8);
    plot(ax_i, t_c_plot*1e3, I_plot(:,2), '-', 'Color', colIb_u, 'LineWidth', 0.8);
    plot(ax_i, t_c_plot*1e3, I_plot(:,3), '-', 'Color', colIc_u, 'LineWidth', 0.8);

    hIa2 = plot(ax_i, t_c_plot*1e3, I_filt_plot(:,1), '-', 'Color', colIa, 'LineWidth', 2.0);
    hIb2 = plot(ax_i, t_c_plot*1e3, I_filt_plot(:,2), '-', 'Color', colIb, 'LineWidth', 2.0);
    hIc2 = plot(ax_i, t_c_plot*1e3, I_filt_plot(:,3), '-', 'Color', colIc, 'LineWidth', 2.0);

    yRi  = ylim(ax_i);
    plot(ax_i, [t_step_ms t_step_ms], yRi, 'r--', 'LineWidth', 2.0);
    text(ax_i, t_step_ms, yRi(2)*0.88, ...
         sprintf('  Step\n  t = %.2f ms', t_step_ms), ...
         'Color', 'r', 'FontSize', 10, 'FontWeight', 'bold', 'VerticalAlignment', 'top');

    % Settling shading
    fill(ax_i, [t_step_ms t_ss_start*1e3 t_ss_start*1e3 t_step_ms], ...
               [yRi(1) yRi(1) yRi(2) yRi(2)], ...
               [1 0.8 0.8], 'FaceAlpha', 0.30, 'EdgeColor', 'none');
    text(ax_i, (t_step_ms + t_ss_start*1e3)/2, yRi(2)*0.72, ...
         sprintf('Settling\n(%.0f cyc)', settlingCycles), ...
         'Color', [0.7 0.1 0.1], 'FontSize', 9, 'FontAngle', 'italic', ...
         'HorizontalAlignment', 'center');

    % SS window shading (if visible in zoom)
    if t_ss_start*1e3 < xLims_zoom(2)
        ss_end_zoom = min(t_ss_end*1e3, xLims_zoom(2));
        fill(ax_i, [t_ss_start*1e3 ss_end_zoom ss_end_zoom t_ss_start*1e3], ...
                   [yRi(1) yRi(1) yRi(2) yRi(2)], ...
                   [0.8 1 0.8], 'FaceAlpha', 0.30, 'EdgeColor', 'none');
        text(ax_i, (t_ss_start*1e3 + ss_end_zoom)/2, yRi(2)*0.72, ...
             'SS Analysis', 'Color', [0.05 0.5 0.05], 'FontSize', 9, ...
             'FontAngle', 'italic', 'HorizontalAlignment', 'center');
    end

    hold(ax_i, 'off');
    xlim(ax_i, xLims_zoom);
    ylabel(ax_i, 'Current  [A]', 'FontSize', 12, 'FontWeight', 'bold');
    xlabel(ax_i, 'Time  [ms]',   'FontSize', 12, 'FontWeight', 'bold');
    legend(ax_i, [hIa2 hIb2 hIc2], ...
           {sprintf('I_{a}  THD = %.2f%%', thdIa), ...
            sprintf('I_{b}  THD = %.2f%%', thdIb), ...
            sprintf('I_{c}  THD = %.2f%%', thdIc)}, ...
           'Location', 'northwest', 'FontSize', 10);
    grid(ax_i, 'on');
    set(ax_i, 'FontSize', 11);

    % Print summary annotation on figure
    annotation(fig2, 'textbox', [0.60 0.02 0.37 0.07], ...
        'String', sprintf(['Metrics computed over post-step SS window  ' ...
                           '[%.2f \x2013 %.2f ms]\n' ...
                           'THD: Ia=%.2f%%  Ib=%.2f%%  Ic=%.2f%%  |  PF = %.4f'], ...
                          t_ss_start*1e3, t_ss_end*1e3, thdIa, thdIb, thdIc, PF_total), ...
        'FontSize', 9.5, 'EdgeColor', [0.5 0.5 0.5], 'LineWidth', 1, ...
        'BackgroundColor', [0.97 0.97 1.00], 'FontWeight', 'normal', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');

    linkaxes([ax_v ax_i], 'x');   % synchronise zoom/pan between panels
end

fprintf('\nDone. %s\n', iif(hasLoadStep, '2 figures generated (overview + step zoom).', '1 figure generated (overview).'));

%% ========================================================================
%  LOCAL FUNCTIONS
%  ========================================================================

function stages = factorizeDecimation(decimFactor)
% Factorises decimFactor into stages each <= 13 for decimate() stability.
    stages    = [];
    remaining = decimFactor;
    for p = [13 11 10 9 8 7 6 5 4 3 2]
        while mod(remaining, p) == 0
            stages(end+1) = p; %#ok<AGROW>
            remaining     = remaining / p;
        end
    end
    if remaining > 1, stages(end+1) = remaining; end
end

function thdPct = computeTHD(x, Fs, f0, maxHarmonic)
% Returns THD (%) of x relative to fundamental f0, harmonics 2..maxHarmonic.
% Uses Hann-windowed FFT with a frequency-tolerance search per harmonic.
    x       = x(:) - mean(x(:));
    N       = length(x);
    w       = hann(N, 'periodic');
    xw      = x .* w;

    Xf      = fft(xw);
    halfN   = floor(N/2) + 1;
    amp     = (2 / sum(w)) * abs(Xf(1:halfN));

    freqRes = Fs / N;
    freqs   = (0:halfN-1) * freqRes;

    maxHarmonic = min(maxHarmonic, floor((Fs/2) / f0));
    tolHz       = max(3 * freqRes, 2);

    harmAmp = zeros(1, maxHarmonic);
    for h = 1:maxHarmonic
        fTarget  = h * f0;
        idxRange = find(freqs >= fTarget - tolHz & freqs <= fTarget + tolHz);
        if isempty(idxRange)
            [~, idxRange] = min(abs(freqs - fTarget));
        end
        harmAmp(h) = max(amp(idxRange));
    end

    thdPct = 100 * sqrt(sum(harmAmp(2:end).^2)) / harmAmp(1);
end

function out = iif(cond, trueVal, falseVal)
% Inline if helper.
    if cond, out = trueVal; else, out = falseVal; end
end

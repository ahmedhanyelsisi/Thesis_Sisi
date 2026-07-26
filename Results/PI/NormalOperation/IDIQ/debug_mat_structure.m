%% debug_mat_structure.m
%  Loads the MAT file selected by the user and prints the COMPLETE
%  structure of the 'out' variable, including field names, sizes,
%  and a sample of actual data values for every numeric array found.
%  Run this FIRST to understand the layout before fixing plot_IDIQ.m

clearvars; clc;

%% 1. File selection (same browse dialog as plot_IDIQ)
scriptDir = fileparts(mfilename('fullpath'));
[fileName, filePath] = uigetfile( ...
    {'*.mat','MAT-files (*.mat)';'*.*','All Files (*.*)'}, ...
    'Select the MAT file to debug', scriptDir);
if isequal(fileName,0)
    disp('Cancelled.'); return;
end
matFile = fullfile(filePath, fileName);
fprintf('Loading: %s\n\n', matFile);
load(matFile, 'out');

%% 2. What class is 'out'?
fprintf('=== out ===\n');
fprintf('  class : %s\n', class(out));
fprintf('  size  : %s\n', mat2str(size(out)));

%% 3. Try to list properties / fields of 'out'
try
    props = fieldnames(out);
    fprintf('  fieldnames(out): %s\n', strjoin(props, ', '));
catch
    try
        props = properties(out);
        fprintf('  properties(out): %s\n', strjoin(props, ', '));
    catch
        fprintf('  [could not list fields/properties]\n');
        props = {};
    end
end
fprintf('\n');

%% 4. Walk every property recursively (depth <= 4)
walk(out, 'out', 0, 4);

%% ---- helper ----
function walk(val, name, depth, maxDepth)
    pad = repmat('  ', 1, depth);
    if depth > maxDepth, return; end

    c = class(val);
    sz = size(val);

    if isnumeric(val) || islogical(val)
        fprintf('%s[%s]  class=%s  size=%s\n', pad, name, c, mat2str(sz));
        if numel(val) <= 10
            fprintf('%s  values: %s\n', pad, mat2str(double(val(:).'), 5));
        else
            v = double(val(:));
            fprintf('%s  min=%.6g  max=%.6g  mean=%.6g  N=%d\n', ...
                pad, min(v), max(v), mean(v,'omitnan'), numel(v));
        end

    elseif ischar(val) || isstring(val)
        s = char(val);
        if length(s) > 120, s = [s(1:117) '...']; end
        fprintf('%s[%s]  "%s"\n', pad, name, s);

    elseif isstruct(val)
        flds = fieldnames(val);
        fprintf('%s[%s]  struct  size=%s  fields: %s\n', ...
            pad, name, mat2str(sz), strjoin(flds,', '));
        for fi = 1:numel(flds)
            f = flds{fi};
            try
                walk(val(1).(f), [name '.' f], depth+1, maxDepth);
            catch ME
                fprintf('%s  .%s  [ERROR: %s]\n', pad, f, ME.message);
            end
        end

    elseif iscell(val)
        fprintf('%s[%s]  cell  size=%s\n', pad, name, mat2str(sz));
        for ci = 1:min(numel(val),3)
            walk(val{ci}, sprintf('%s{%d}', name, ci), depth+1, maxDepth);
        end

    else
        % MATLAB objects (timeseries, Dataset, etc.)
        fprintf('%s[%s]  class=%s  size=%s\n', pad, name, c, mat2str(sz));
        try
            flds = fieldnames(val);
            if ~isempty(flds)
                fprintf('%s  fieldnames: %s\n', pad, strjoin(flds,', '));
                for fi = 1:numel(flds)
                    f = flds{fi};
                    try
                        walk(val.(f), [name '.' f], depth+1, maxDepth);
                    catch ME2
                        fprintf('%s  .%s [ERROR: %s]\n', pad, f, ME2.message);
                    end
                end
            end
        catch
        end
        try
            props = properties(val);
            if ~isempty(props)
                fprintf('%s  properties: %s\n', pad, strjoin(props,', '));
                for pi = 1:numel(props)
                    p = props{pi};
                    try
                        walk(val.(p), [name '.' p], depth+1, maxDepth);
                    catch ME3
                        fprintf('%s  .%s [ERROR: %s]\n', pad, p, ME3.message);
                    end
                end
            end
        catch
        end
    end
end

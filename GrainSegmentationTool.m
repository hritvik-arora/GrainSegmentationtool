    function GrainSegmentationTool()
    % =========================================================================
    % GrainSegmentationTool.m
    % Interactive Microstructural Grain Segmentation Tool
    %
    % DESCRIPTION:
    %   A complete, standalone MATLAB application for segmenting grain
    %   boundaries in microstructure images using the watershed transform.
    %   Features a dark-themed GUI with real-time parameter adjustment,
    %   manual boundary editing, and binary BMP export.
    %
    % REQUIREMENTS:
    %   - MATLAB R2019b or later
    %   - Image Processing Toolbox
    %
    % USAGE:
    %   Run this function directly: >> GrainSegmentationTool()
    %
    % VERSION: 1.5
    %   - Added Undo / Redo system (unlimited history stack).
    %     pushUndo() is called automatically before every Draw or Erase edit.
    %   - Added Save Project: serialises the full session (image, masks,
    %     tolerance, undo/redo stacks, zoom state) to a .mat file.
    %   - Added Load Project: restores a saved session and resumes editing,
    %     including full undo/redo continuity.
    % =========================================================================
    
        %% -------------------------------------------------------------------
        %  Toolbox guard
        %  -------------------------------------------------------------------
        if ~license('test', 'image_toolbox')
            errordlg('Image Processing Toolbox is required but not found.', ...
                     'Missing Toolbox');
            return;
        end
    
        %% -------------------------------------------------------------------
        %  APPLICATION STATE
        %  All mutable data lives here. Shared across all callbacks via
        %  MATLAB nested-function closure (no globals needed).
        %
        %  KEY DESIGN RULE: appState.eraseMask and appState.drawMask are the
        %  SINGLE SOURCE OF TRUTH for manual edits.  They accumulate across
        %  every Draw/Erase action and are NEVER reset by slider changes.
        %  Only loading a new image resets them.
        %  -------------------------------------------------------------------
        appState = struct();
        appState.originalGray = [];       % uint8 grayscale of the loaded image
        appState.imageLoaded  = false;
        appState.originalRGB  = [];
        appState.hImage = [];
        appState.tolerance    = 22;       % watershed tolerance (slider value)
        appState.eraseMask    = [];       % logical – cumulative erased zones
        appState.drawMask     = [];       % logical – cumulative drawn boundaries
        appState.undoStack    = {};       % cell array of {eraseMask, drawMask} snapshots
        appState.redoStack    = {};       % cell array of {eraseMask, drawMask} snapshots
        appState.isModified   = false;    % true whenever unsaved changes exist
    
        %% -------------------------------------------------------------------
        %  COLOR PALETTE  (dark theme)
        %  -------------------------------------------------------------------
        CLR.bg          = [0.12  0.13  0.15];
        CLR.panel       = [0.16  0.18  0.21];
        CLR.panelBorder = [0.25  0.28  0.33];
        CLR.accent      = [0.20  0.65  1.00];
        CLR.accentDim   = [0.10  0.35  0.55];
        CLR.btnText     = [1.00  1.00  1.00];
        CLR.labelText   = [0.78  0.82  0.88];
        CLR.valueText   = [0.95  0.97  1.00];
        CLR.overlayLine = [1  0  0];   % white watershed lines
        CLR.drawBtn     = [0.15  0.70  0.45];
        CLR.eraseBtn    = [0.80  0.30  0.20];
        CLR.saveBtn     = [0.55  0.20  0.85];
    
        %% -------------------------------------------------------------------
        %  MAIN FIGURE
        %  -------------------------------------------------------------------
        figW = 1200;  figH = 780;
        ss   = get(0, 'ScreenSize');
        hFig = figure( ...
            'Name',            'Grain Segmentation Tool  v1.5', ...
            'NumberTitle',     'off', ...
            'MenuBar',         'none', ...
            'ToolBar',         'none', ...
            'Color',           CLR.bg, ...
            'Position',        [(ss(3)-figW)/2, (ss(4)-figH)/2, figW, figH], ...
            'Resize',          'on', ...
            'CloseRequestFcn', @onClose);
        hFig.WindowScrollWheelFcn = @onMouseWheel;
    
        %% -------------------------------------------------------------------
        %  LAYOUT CONSTANTS
        %  -------------------------------------------------------------------
        panelW  = 270;
        margin  = 14;
        btnH    = 38;
        lblH    = 18;
        sliderH = 22;
        secGap  = 18;
    
        %% -------------------------------------------------------------------
        %  LEFT CONTROL PANEL
        %  -------------------------------------------------------------------
        hPanel = uipanel(hFig, ...
            'Units',           'pixels', ...
            'Position',        [0 0 panelW figH], ...
            'BackgroundColor', CLR.panel, ...
            'BorderType',      'line', ...
            'HighlightColor',  CLR.panelBorder, ...
            'ForegroundColor', CLR.btnText);
    
        % App title
        uicontrol(hPanel, 'Style','text', 'String','GRAIN SEGMENTOR', ...
            'Units','pixels', 'Position',[margin figH-30 panelW-2*margin 38], ...
            'FontSize',15, 'FontWeight','bold', 'FontName','Helvetica', ...
            'BackgroundColor',CLR.panel, 'ForegroundColor',CLR.accent, ...
            'HorizontalAlignment','center');
        uicontrol(hPanel, 'Style','text', 'String','Microstructural Analysis', ...
            'Units','pixels', 'Position',[margin figH-50 panelW-2*margin 18], ...
            'FontSize',9, 'BackgroundColor',CLR.panel, ...
            'ForegroundColor',CLR.labelText, 'HorizontalAlignment','center');
        makeSep(hPanel, margin, figH-62, panelW-2*margin, CLR.panelBorder);
    
        %% IMAGE INPUT section
        curY = figH - 62 - secGap;
        makeLbl(hPanel,'IMAGE INPUT',margin,curY,panelW-2*margin,lblH, ...
                CLR.accent,CLR.panel,9,'bold');
        curY = curY - lblH - 4;
    
        hLoadBtn = makeBtn(hPanel,'Load Image',margin,curY,panelW-2*margin,btnH, ...
                           CLR.accent,CLR.btnText);
        hLoadBtn.Callback = @onLoadImage;
        curY = curY - btnH - 6;
    
        hFileLabel = uicontrol(hPanel,'Style','text','String','No file loaded', ...
            'Units','pixels','Position',[margin curY panelW-2*margin lblH+4], ...
            'FontSize',8,'BackgroundColor',CLR.panel,'ForegroundColor',CLR.labelText, ...
            'HorizontalAlignment','center');
        curY = curY - (lblH+4) - secGap;
            hLoadProjBtn = makeBtn(hPanel,'Load Project (.mat)',margin,curY, ...
                               panelW-2*margin,btnH,CLR.accent,CLR.btnText);
        hLoadProjBtn.Callback = @onLoadProject;
        curY = curY - btnH - secGap;
        makeSep(hPanel, margin, curY+secGap/2, panelW-2*margin, CLR.panelBorder);
    
        %% WATERSHED TOLERANCE section
        makeLbl(hPanel,'WATERSHED TOLERANCE',margin,curY,panelW-2*margin,lblH, ...
                CLR.accent,CLR.panel,9,'bold');
        curY = curY - lblH - 2;
        makeLbl(hPanel,'Tolerance:',margin,curY,90,lblH, ...
                CLR.labelText,CLR.panel,9,'normal');
    
        hTolValue = uicontrol(hPanel,'Style','text', ...
            'String',num2str(appState.tolerance), ...
            'Units','pixels','Position',[panelW-margin-55 curY 55 lblH], ...
            'FontSize',13,'FontWeight','bold','BackgroundColor',CLR.panel, ...
            'ForegroundColor',CLR.valueText,'HorizontalAlignment','right');
        curY = curY - sliderH - 4;
    
        hSlider = uicontrol(hPanel,'Style','slider','Min',1,'Max',100, ...
            'Value',appState.tolerance,'Units','pixels', ...
            'Position',[margin curY panelW-2*margin sliderH], ...
            'BackgroundColor',CLR.accentDim);
    
        % Real-time label while dragging; re-segment on release
        addlistener(hSlider,'Value','PostSet',@onSliderDrag);
        hSlider.Callback = @onSliderRelease;
    
        curY = curY - sliderH - 2;
        makeLbl(hPanel,'1',margin,curY,30,lblH-4,CLR.labelText,CLR.panel,8,'normal');
        makeLbl(hPanel,'100',panelW-margin-30,curY,30,lblH-4, ...
                CLR.labelText,CLR.panel,8,'normal');
        curY = curY - (lblH-4) - secGap;
        makeLbl(hPanel,sprintf('Low = fine detail\nHigh = coarser grains'), ...
                margin,curY,panelW-2*margin,32,CLR.labelText,CLR.panel,8,'normal');
        curY = curY - 32 - secGap;
        makeSep(hPanel, margin, curY+secGap/2, panelW-2*margin, CLR.panelBorder);
    
        %% MANUAL CORRECTIONS section
        makeLbl(hPanel,'MANUAL CORRECTIONS',margin,curY,panelW-2*margin,lblH, ...
                CLR.accent,CLR.panel,9,'bold');
        curY = curY - lblH - 6;
        makeLbl(hPanel,'Draw or erase boundary lines directly on the image.', ...
                margin,curY,panelW-2*margin,28,CLR.labelText,CLR.panel,8,'normal');
        curY = curY - 28 - 6;
    
        hDrawBtn = makeBtn(hPanel,'✏  Draw Boundary',margin,curY, ...
                           panelW-2*margin,btnH,CLR.drawBtn,CLR.btnText);
        hDrawBtn.Callback = @onDrawBoundary;
        curY = curY - btnH - 6;
    
        hEraseBtn = makeBtn(hPanel,'✕  Erase Boundary',margin,curY, ...
                            panelW-2*margin,btnH,CLR.eraseBtn,CLR.btnText);
        hEraseBtn.Callback = @onEraseBoundary;
        curY = curY - btnH - 6;
    
        hApplyEditsBtn = makeBtn(hPanel,'✔  Apply Edits',margin,curY, ...
                                 panelW-2*margin,btnH,CLR.accent,CLR.btnText);
        hApplyEditsBtn.Callback = @onApplyEdits;
        curY = curY - btnH - 6;
    
        % Undo / Redo side-by-side
        halfW = (panelW - 2*margin - 6) / 2;
        hUndoBtn = makeBtn(hPanel,'<html>&#8617; Undo</html>',margin,curY,halfW,btnH, ...
                           [0.30 0.35 0.45],CLR.btnText);
        hUndoBtn.Callback = @onUndo;
        hRedoBtn = makeBtn(hPanel,'<html>&#8618; Redo</html>',margin+halfW+6,curY,halfW,btnH, ...
                           [0.30 0.35 0.45],CLR.btnText);
        hRedoBtn.Callback = @onRedo;
        curY = curY - btnH - secGap;
        makeSep(hPanel, margin, curY+secGap/2, panelW-2*margin, CLR.panelBorder);
    
        %% PROJECT section
        makeLbl(hPanel,'PROJECT',margin,curY,panelW-2*margin,lblH, ...
                CLR.accent,CLR.panel,9,'bold');
        curY = curY - lblH - 6;
        makeLbl(hPanel,'Save or load a full editing session.', ...
                margin,curY,panelW-2*margin,24,CLR.labelText,CLR.panel,8,'normal');
        curY = curY - 24 - 6;
    
        hSaveProjBtn = makeBtn(hPanel,'Save Project (.mat)',margin,curY, ...
                               panelW-2*margin,btnH,[0.20 0.50 0.35],CLR.btnText);
        hSaveProjBtn.Callback = @onSaveProject;
        curY = curY - btnH - 6;
    
        makeSep(hPanel, margin, curY+secGap/2, panelW-2*margin, CLR.panelBorder);
    
        %% EXPORT section
        hSaveBtn = makeBtn(hPanel,'💾  Save Boundaries (.bmp)',margin,curY, ...
                           panelW-2*margin,btnH,CLR.saveBtn,CLR.btnText);
        hSaveBtn.Callback = @onSave;
        curY = curY - btnH - secGap; %#ok<NASGU>
    
        %% STATUS BAR
        hStatus = uicontrol(hPanel,'Style','text', ...
            'String','Ready.  Load an image to begin.', ...
            'Units','pixels','Position',[margin 8 panelW-2*margin 36], ...
            'FontSize',8,'BackgroundColor',CLR.panel,'ForegroundColor',CLR.labelText, ...
            'HorizontalAlignment','center');
    
        %% -------------------------------------------------------------------
        %  IMAGE DISPLAY AXES
        %  -------------------------------------------------------------------
        hAxes = axes(hFig, ...
            'Units',    'pixels', ...
            'Position', [panelW+10, 10, figW-panelW-20, figH-20], ...
            'Color',    [0.08 0.09 0.11], ...
            'XColor',   CLR.panelBorder, ...
            'YColor',   CLR.panelBorder, ...
            'Box',      'on');
        axis(hAxes,'equal','tight');
        text(hAxes, 0.5, 0.5, ...
            sprintf('Load a microstructure image\nto begin segmentation'), ...
            'Units','normalized','HorizontalAlignment','center', ...
            'VerticalAlignment','middle','Color',CLR.labelText, ...
            'FontSize',14,'FontName','Helvetica');
        set(hAxes,'XTick',[],'YTick',[]);
    
        hFig.SizeChangedFcn = @onFigResize;
    
        %% ===================================================================
        %  CALLBACKS
        %  ===================================================================
    
        function onClose(~,~)
            % ------------------------------------------------------------------
            %  Unsaved-Changes Protection
            %  If no edits have been made since the last save (or since launch),
            %  close immediately.  Otherwise present a three-button dialog that
            %  lets the user Save & Exit, discard changes, or cancel entirely.
            % ------------------------------------------------------------------
            if ~appState.isModified
                delete(hFig);
                return;
            end
    
            choice = questdlg( ...
                sprintf('You have unsaved changes.\n\nDo you want to save your project before exiting?'), ...
                'Unsaved Changes', ...
                'Save & Exit', 'Exit Without Saving', 'Cancel', ...
                'Save & Exit');   % default button
    
            switch choice
                case 'Save & Exit'
                    % Run the existing save routine.  onSaveProject returns
                    % normally whether the user completed the save or pressed
                    % Cancel in the file-chooser.  We detect a successful save
                    % by checking whether isModified was cleared afterwards.
                    onSaveProject([], []);
                    if ~appState.isModified
                        % Save completed — safe to close.
                        delete(hFig);
                    end
                    % If isModified is still true the user cancelled the file
                    % dialog; fall through without closing.
    
                case 'Exit Without Saving'
                    delete(hFig);
    
                otherwise
                    % 'Cancel' or dialog closed with the X button — do nothing.
            end
        end
    
        % -------------------------------------------------------------------
        function onFigResize(~,~)
            pos = hFig.Position;
            hAxes.Position  = [panelW+10, 10, pos(3)-panelW-20, pos(4)-20];
            hPanel.Position = [0, 0, panelW, pos(4)];
        end
    
        % -------------------------------------------------------------------
        function onLoadImage(~,~)
            [fname, fpath] = uigetfile( ...
                {'*.bmp;*.png;*.jpg;*.jpeg;*.tif;*.tiff','Image Files'; ...
                 '*.*','All Files'}, ...
                'Select Microstructure Image');
            if isequal(fname,0); return; end
    
            setStatus('Loading image…');
            drawnow;
    
            try
                raw = imread(fullfile(fpath, fname));
                appState.originalRGB = raw;
            catch ME
                errordlg(sprintf('Cannot read image:\n%s', ME.message),'Load Error');
                setStatus('Error: could not load image.');
                return;
            end
    
            % Auto-convert to 8-bit grayscale
            if ndims(raw) == 3
                gray = rgb2gray(raw(:,:,1:3));
            else
                gray = raw;
            end
            if ~isa(gray,'uint8')
                gray = im2uint8(gray);
            end
    
            appState.originalGray = gray;
            appState.imageLoaded  = true;
    
            % Reset BOTH manual masks for the new image
            [r,c] = size(gray);
            appState.eraseMask = false(r,c);
            appState.drawMask  = false(r,c);
            appState.undoStack = {};
            appState.redoStack = {};
    
            % Truncate long filenames for display
            dn = fname;
            if numel(dn) > 30; dn = ['...' dn(end-27:end)]; end
            hFileLabel.String = dn;
    
            setStatus(sprintf('Loaded %d×%d px — running segmentation…', c, r));
            drawnow;
    
            appState.isModified = true;   % new image = unsaved project state
            updateDisplay();    % single entry point for everything
            setStatus('Done.  Adjust Tolerance or use Draw / Erase.');
        end
    
        % -------------------------------------------------------------------
        function onSliderDrag(~,~)
            % Update numeric label in real time while the thumb is being dragged.
            % Do NOT re-segment here — that only happens on release.
            hTolValue.String = num2str(round(hSlider.Value));
        end
    
        % -------------------------------------------------------------------
        function onSliderRelease(~,~)
            val = round(hSlider.Value);
            hSlider.Value      = val;           % snap to integer
            hTolValue.String   = num2str(val);
            appState.tolerance = val;
    
            if appState.imageLoaded
                setStatus(sprintf('Tolerance → %d — re-segmenting…', val));
                drawnow;
                appState.isModified = true;   % tolerance change = unsaved state
                updateDisplay();   % recomputes watershed AND reapplies all masks
                setStatus(sprintf('Done.  Tolerance = %d.', val));
            end
        end
    
        % -------------------------------------------------------------------
        function onDrawBoundary(~,~)
            if ~appState.imageLoaded
                setStatus('Load an image first.');
                return;
            end
    
            setStatus('DRAW — draw a line, then double-click or press Enter to commit.');
            drawnow;
    
            axes(hAxes); %#ok<LAXES>
            roi = [];
            try
                roi = drawfreehand(hAxes, ...
                    'Color',     [0.20 1.00 0.50], ...
                    'LineWidth', 2, ...
                    'Closed',    false);
                wait(roi);
            catch ME
                setStatus(sprintf('Draw cancelled (%s).', ME.message));
                try; delete(roi); catch; end
                return;
            end
    
            if ~isvalid(roi)
                setStatus('Draw cancelled.');
                return;
            end
    
            pos = roi.Position;
    
            % --- CRITICAL: delete ROI BEFORE touching the axes ---
            delete(roi);
    
            if isempty(pos) || size(pos,1) < 2
                setStatus('Draw cancelled — path too short.');
                return;
            end
    
            % Rasterise the drawn stroke
            [nR,nC]   = size(appState.originalGray);
            newPixels = rasterisePath(pos, nR, nC);
    
            % Save state for undo BEFORE modifying masks
            pushUndo();
    
            % Accumulate into draw mask; drawn pixels supersede prior erasures
            appState.drawMask              = appState.drawMask  | newPixels;
            appState.eraseMask(newPixels)  = false;
            appState.isModified            = true;   % draw = unsaved change
    
            % Auto-update disabled — user must press "Apply Edits" to refresh.
            % updateDisplay();
            setStatus('Line recorded. Click ''Apply Edits'' to refresh the display.');
        end
    
        % -------------------------------------------------------------------
        function onEraseBoundary(~,~)
            if ~appState.imageLoaded
                setStatus('Load an image first.');
                return;
            end
    
            setStatus('ERASE — draw over a boundary to delete it, then double-click or press Enter.');
            drawnow;
    
            axes(hAxes); %#ok<LAXES>
            roi = [];
            try
                roi = drawfreehand(hAxes, ...
                    'Color',     [1.00 0.35 0.20], ...
                    'LineWidth', 2, ...
                    'Closed',    true);
                wait(roi);
            catch ME
                setStatus(sprintf('Erase cancelled (%s).', ME.message));
                try; delete(roi); catch; end
                return;
            end
    
            if ~isvalid(roi)
                setStatus('Erase cancelled.');
                return;
            end
    
            pos = roi.Position;
    
            % --- CRITICAL: delete ROI BEFORE touching the axes ---
            % This removes the red ROI graphic from the figure so it cannot
            % bleed into the composited image during the next imshow call.
            delete(roi);
    
            if isempty(pos) || size(pos,1) < 2
                setStatus('Erase cancelled — path too short.');
                return;
            end
    
            % Fill the entire polygon enclosed by the freehand stroke.
            % poly2mask converts the (x,y) outline into a filled logical mask —
            % every pixel inside the drawn region is erased, not just the stroke.
            [nR,nC]    = size(appState.originalGray);
            filledErase = poly2mask(pos(:,1), pos(:,2), nR, nC);
    
            % Save state for undo BEFORE modifying masks
            pushUndo();
    
            % Accumulate into the erase mask (cumulative OR — history preserved)
            appState.eraseMask             = appState.eraseMask | filledErase;
            % Remove any previously drawn pixels in the same zone
            appState.drawMask(filledErase) = false;
            appState.isModified            = true;   % erase = unsaved change
    
            % Auto-update disabled — user must press "Apply Edits" to refresh.
            % updateDisplay();
            setStatus('Line recorded. Click ''Apply Edits'' to refresh the display.');
        end
    
        % -------------------------------------------------------------------
        %  UNDO / REDO HELPER
        %  Call pushUndo() BEFORE applying any mask change so the previous
        %  state is captured.  Pushing a new edit always clears the redo stack.
        % -------------------------------------------------------------------
        function pushUndo()
            snapshot = struct('eraseMask', appState.eraseMask, ...
                              'drawMask',  appState.drawMask);
            appState.undoStack{end+1} = snapshot;
            fprintf('PUSH: undo stack size = %d\n', numel(appState.undoStack));
            appState.redoStack = {};          % new edit invalidates redo history
        end
    
        % -------------------------------------------------------------------
        function onUndo(~,~)
            fprintf('UNDO BEFORE: undo=%d redo=%d\n', ...
                numel(appState.undoStack), ...
                numel(appState.redoStack));
            disp('UNDO CLICKED');
            persistent busy
    
            if ~isempty(busy) && busy
                return;
            end
    
            busy = true;
    
            try
                if ~appState.imageLoaded
                    setStatus('Load an image first.');
                    return;
                end
                if isempty(appState.undoStack)
                    setStatus('Nothing to undo.');
                    return;
                end
            % Push current state onto redo stack
            redoSnap = struct('eraseMask', appState.eraseMask, ...
                              'drawMask',  appState.drawMask);
            appState.redoStack{end+1} = redoSnap;
            % Pop the most recent undo snapshot and restore it
            snap = appState.undoStack{end};
            appState.undoStack(end) = [];
            appState.eraseMask = snap.eraseMask;
            appState.drawMask  = snap.drawMask;
            updateDisplay();
            setStatus(sprintf('Undo applied.  (%d step(s) remaining)', ...
                              numel(appState.undoStack)));
            busy = false;
    
            catch ME
                busy = false;
                rethrow(ME);
            end
            fprintf('UNDO AFTER: undo=%d redo=%d\n', ...
                numel(appState.undoStack), ...
                numel(appState.redoStack));
        end
    
        % -------------------------------------------------------------------
        function onRedo(~,~)
            fprintf('REDO BEFORE: undo=%d redo=%d\n', ...
                numel(appState.undoStack), ...
                numel(appState.redoStack));
            persistent busy
    
            if ~isempty(busy) && busy
                return;
            end
    
            busy = true;
    
            try
            if ~appState.imageLoaded
                setStatus('Load an image first.');
                return;
            end
            if isempty(appState.redoStack)
                setStatus('Nothing to redo.');
                return;
            end
            % Push current state onto undo stack so undo still works after redo
            undoSnap = struct('eraseMask', appState.eraseMask, ...
                              'drawMask',  appState.drawMask);
            appState.undoStack{end+1} = undoSnap;
            % Pop the most recent redo snapshot and restore it
            snap = appState.redoStack{end};
            appState.redoStack(end) = [];
            appState.eraseMask = snap.eraseMask;
            appState.drawMask  = snap.drawMask;
            updateDisplay();
            setStatus(sprintf('Redo applied.  (%d step(s) remaining)', ...
                              numel(appState.redoStack)));
            busy = false;
    
            catch ME
                busy = false;
                rethrow(ME);
            end
            fprintf('REDO AFTER: undo=%d redo=%d\n', ...
                numel(appState.undoStack), ...
                numel(appState.redoStack));
        end
    
        % -------------------------------------------------------------------
        function onSaveProject(~,~)
            if ~appState.imageLoaded
                setStatus('Nothing to save — load and segment an image first.');
                return;
            end
    
            [fname, fpath] = uiputfile( ...
                {'*.mat','MATLAB Project File (*.mat)'}, ...
                'Save Project As…', ...
                'grain_project.mat');
            if isequal(fname,0); return; end
    
            setStatus('Saving project…');
            drawnow;
    
            % Capture current axes limits (zoom / pan state)
            xl = xlim(hAxes);
            yl = ylim(hAxes);
    
            project = struct();
            project.originalGray  = appState.originalGray;
            project.originalRGB   = appState.originalRGB;
            project.eraseMask     = appState.eraseMask;
            project.drawMask      = appState.drawMask;
            project.tolerance     = appState.tolerance;
            project.undoStack     = {appState.undoStack};   % wrap so save handles cell-of-cells
            project.redoStack     = {appState.redoStack};
            project.xlim          = xl;
            project.ylim          = yl;
            project.version       = '1.5';
    
            try
                save(fullfile(fpath, fname), 'project');
                appState.isModified = false;   % project is now saved and up-to-date
                setStatus(sprintf('Project saved: %s', fname));
                msgbox(sprintf('Project saved:\n%s', fullfile(fpath,fname)), ...
                       'Save Successful','help');
            catch ME
                errordlg(sprintf('Save failed:\n%s', ME.message),'Save Error');
                setStatus('Error saving project.');
            end
        end
    
        % -------------------------------------------------------------------
        function onLoadProject(~,~)
            [fname, fpath] = uigetfile( ...
                {'*.mat','MATLAB Project File (*.mat)'; '*.*','All Files'}, ...
                'Open Project…');
            if isequal(fname,0); return; end
    
            setStatus('Loading project…');
            drawnow;
    
            try
                S = load(fullfile(fpath, fname), 'project');
            catch ME
                errordlg(sprintf('Cannot read file:\n%s', ME.message),'Load Error');
                setStatus('Error: could not read project file.');
                return;
            end
    
            if ~isfield(S,'project')
                errordlg('This file does not contain a valid GrainSegmentor project.', ...
                         'Load Error');
                setStatus('Error: not a project file.');
                return;
            end
            p = S.project;
    
            % Validate required fields
            required = {'originalGray','originalRGB','eraseMask','drawMask','tolerance'};
            for k = 1:numel(required)
                if ~isfield(p, required{k})
                    errordlg(sprintf('Project file is missing field: %s', required{k}), ...
                             'Load Error');
                    setStatus('Error: corrupt or old project file.');
                    return;
                end
            end
    
            % Restore all state
            appState.originalGray = p.originalGray;
            appState.originalRGB  = p.originalRGB;
            appState.eraseMask    = p.eraseMask;
            appState.drawMask     = p.drawMask;
            appState.tolerance    = p.tolerance;
            appState.imageLoaded  = true;
            appState.hImage       = [];   % force fresh imshow on first render
    
            % Restore undo / redo stacks (unwrap the outer cell if present)
            if isfield(p,'undoStack') && iscell(p.undoStack) && ~isempty(p.undoStack)
                appState.undoStack = p.undoStack{1};
            else
                appState.undoStack = {};
            end
            if isfield(p,'redoStack') && iscell(p.redoStack) && ~isempty(p.redoStack)
                appState.redoStack = p.redoStack{1};
            else
                appState.redoStack = {};
            end
    
            % Sync slider
            hSlider.Value    = appState.tolerance;
            hTolValue.String = num2str(appState.tolerance);
    
            % Show a short filename in the label
            dn = fname;
            if numel(dn) > 30; dn = ['...' dn(end-27:end)]; end
            hFileLabel.String = ['[Project] ' dn];
    
            % Render image with restored masks
            updateDisplay();
    
            % Restore zoom / pan if available
            if isfield(p,'xlim') && isfield(p,'ylim')
                xlim(hAxes, p.xlim);
                ylim(hAxes, p.ylim);
            end
    
            setStatus(sprintf('Project loaded. Undo: %d  Redo: %d', ...
                              numel(appState.undoStack), numel(appState.redoStack)));
            appState.isModified = false;   % freshly loaded project has no unsaved changes
        end
    
        % -------------------------------------------------------------------
        function onApplyEdits(~,~)
            if ~appState.imageLoaded
                return;
            end
            appState.isModified = true;   % applying edits = unsaved change
            updateDisplay();
            setStatus('Edits applied successfully.');
        end
    
        % -------------------------------------------------------------------
        function onSave(~,~)
            if ~appState.imageLoaded
                setStatus('Nothing to save — load and segment an image first.');
                return;
            end
    
            [fname, fpath] = uiputfile( ...
                {'*.bmp','BMP Image (*.bmp)'}, ...
                'Save Boundary Lines As…', ...
                'grain_boundaries.bmp');
            if isequal(fname,0); return; end
    
            % Compute the final boundary mask (same pipeline as display)
            finalMask = computeFinalMask();
    
            % Export: black lines (0) on white background (255)  — pure binary BMP
            exportImg = uint8(~finalMask) * 255;
    
            try
                imwrite(exportImg, fullfile(fpath, fname), 'bmp');
                setStatus(sprintf('Saved: %s', fname));
                msgbox(sprintf('Saved:\n%s', fullfile(fpath,fname)), ...
                       'Save Successful','help');
            catch ME
                errordlg(sprintf('Save failed:\n%s', ME.message),'Save Error');
                setStatus('Error saving file.');
            end
        end
    
        %% ===================================================================
        %  CORE PIPELINE  —  updateDisplay()
        %
        %  THIS IS THE SINGLE AUTHORITATIVE RENDER FUNCTION.
        %  It is called by every action that should change what is on screen:
        %    • Image load
        %    • Slider release
        %    • Draw finished
        %    • Erase finished
        %
        %  Steps run in this FIXED order every time, guaranteeing that manual
        %  erasures always override the freshly computed watershed result:
        %
        %    (a) Morphological gradient
        %    (b) Watershed transform  →  raw dam mask  (L == 0)
        %    (c) Apply erase mask     →  remove user-erased pixels
        %    (d) Apply draw mask      →  add user-drawn pixels
        %    (e) Render overlay       →  imshow + drawnow
        %  ===================================================================
    
        function updateDisplay()
            if ~appState.imageLoaded; return; end
            finalMask = computeFinalMask();
            renderToAxes(finalMask);
        end
    
        % -------------------------------------------------------------------
        function finalMask = computeFinalMask()
            % Returns the logical boundary mask that represents the current
            % state: watershed + draws - erasures.  Used by both updateDisplay
            % and onSave so both always produce identical results.
    
            img = appState.originalGray;
            tol = appState.tolerance;
    
            %% (a) Morphological gradient with disk SE radius 1
            %  Dilation - erosion highlights intensity transitions at grain edges.
            se        = strel('disk', 1);
            morphGrad = imsubtract(imdilate(img, se), imerode(img, se));
    
            %% (b) Watershed transform
            %  imextendedmin selects only minima deeper than 'tol' (noise filter).
            %  imimposemin enforces those as the only true minima so the watershed
            %  floods from them exclusively → controls grain count.
            extMin   = imextendedmin(morphGrad, tol);
            modGrad  = imimposemin(morphGrad, extMin);
            L        = watershed(modGrad, 8);   % 8-connectivity
    
            % Raw watershed dam pixels (label == 0 in the label matrix)
            damMask  = (L == 0);
            damMask = imdilate(damMask, strel('disk',1));
    
            %% (c) Apply erase mask
            %  Remove every pixel in appState.eraseMask from the dam result.
            %  Formula: finalDams = rawDams & ~eraseMask
            damMask(appState.eraseMask) = false;
    
            %% (d) Apply draw mask, then enforce erase mask over everything
            %  The erase mask must win over both watershed dams AND user-drawn
            %  lines.  Without the second step, a drawn stroke that overlaps an
            %  erased zone would re-introduce pixels through the OR.
            %  Formula: finalMask = (damMask | drawMask) & ~eraseMask
            combinedMask = damMask | appState.drawMask;
            finalMask    = combinedMask & ~appState.eraseMask;
        end
    
        % -------------------------------------------------------------------
    function renderToAxes(boundaryMask)
            rgb = appState.originalRGB;
    
            R = rgb(:,:,1);
            G = rgb(:,:,2);
            B = rgb(:,:,3);
    
            ov = CLR.overlayLine;
            R(boundaryMask) = uint8(ov(1) * 255);
            G(boundaryMask) = uint8(ov(2) * 255);
            B(boundaryMask) = uint8(ov(3) * 255);
    
            rgb = cat(3, R, G, B);
    
            % --- SOLUTION TO ZOOM BUG ---
            % If the image object already exists, update its raw pixel properties directly.
            % This completely prevents view reset, frame snapping, and display flickering.
            if isfield(appState, 'hImage') && ~isempty(appState.hImage) && isvalid(appState.hImage)
                appState.hImage.CData = rgb;
            else
                % This runs ONLY during initialization or when opening a completely fresh file.
                cla(hAxes);
                appState.hImage = imshow(rgb, 'Parent', hAxes);
                axtoolbar(hAxes,{'zoomin','zoomout','pan','restoreview'});
                set(hAxes, 'XColor', CLR.panelBorder, 'YColor', CLR.panelBorder, 'Box','on');
                axis(hAxes, 'image');
            end
    
            drawnow;    
        end
    
        %% ===================================================================
        %  UTILITY FUNCTIONS
        %  ===================================================================
    
        function mask = rasterisePath(positions, nRows, nCols)
            % Convert an N×2 [x y] position array from a drawfreehand ROI into
            % a logical pixel mask using dense Bresenham-style sampling along
            % each segment of the polyline.
            %
            % The result is slightly dilated (disk r=1) to make drawn lines
            % 2-3 px wide for easier visual inspection.
    
            mask = false(nRows, nCols);
            if isempty(positions) || size(positions,1) < 2; return; end
    
            for k = 1 : size(positions,1)-1
                x1 = positions(k,  1);  y1 = positions(k,  2);
                x2 = positions(k+1,1);  y2 = positions(k+1,2);
    
                nSamples = ceil(max(abs(x2-x1), abs(y2-y1))) + 1;
                nSamples = max(nSamples, 2);
    
                xs = round(linspace(x1, x2, nSamples));
                ys = round(linspace(y1, y2, nSamples));
    
                xs = max(1, min(nCols, xs));
                ys = max(1, min(nRows, ys));
    
                mask(sub2ind([nRows,nCols], ys, xs)) = true;
            end
    
            % Thin dilation: makes the drawn line visible without being obtrusive
            mask = imdilate(mask, strel('disk', 1));
        end
    
        % -------------------------------------------------------------------
        function setStatus(msg)
            if isvalid(hStatus)
                hStatus.String = msg;
                drawnow limitrate;
            end
        end
    
        % -------------------------------------------------------------------
        function h = makeBtn(parent, label, x, y, w, ht, bg, fg)
            h = uicontrol(parent, 'Style','pushbutton', 'String',label, ...
                'Units','pixels', 'Position',[x y w ht], ...
                'FontSize',10, 'FontWeight','bold', 'FontName','Helvetica', ...
                'BackgroundColor',bg, 'ForegroundColor',fg);
        end
    
        % -------------------------------------------------------------------
        function makeLbl(parent, str, x, y, w, ht, fg, bg, sz, wt)
            uicontrol(parent, 'Style','text', 'String',str, ...
                'Units','pixels', 'Position',[x y w ht], ...
                'FontSize',sz, 'FontWeight',wt, 'FontName','Helvetica', ...
                'BackgroundColor',bg, 'ForegroundColor',fg, ...
                'HorizontalAlignment','left');
        end
    
        % -------------------------------------------------------------------
        function makeSep(parent, x, y, w, color)
            uipanel(parent, 'Units','pixels', 'Position',[x y w 1], ...
                'BackgroundColor',color, 'BorderType','none');
        end
        function onMouseWheel(~,evt)
    
            if ~appState.imageLoaded
                return;
            end
    
            xl = xlim(hAxes);
            yl = ylim(hAxes);
    
            cx = mean(xl);
            cy = mean(yl);
    
            if evt.VerticalScrollCount < 0
                scale = 0.8;      % zoom in
            else
                scale = 1.25;     % zoom out
            end
    
            w = diff(xl) * scale;
            h = diff(yl) * scale;
    
            xlim(hAxes,[cx-w/2 cx+w/2]);
            ylim(hAxes,[cy-h/2 cy+h/2]);
    
        end
    
    end  % ===== end GrainSegmentationTool =====
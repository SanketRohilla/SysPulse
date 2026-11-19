#import <Cocoa/Cocoa.h>
#import <IOKit/IOKitLib.h>
#import <mach/mach.h>
#import <mach/processor_info.h>
#import <mach/mach_host.h>
#import <sys/sysctl.h>
#import <sys/mount.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <arpa/inet.h>

#define TJ_MAX 100.0f
#define GRAPH_CAPACITY 60

// -----------------------------------------------------------------------------
// SMC Structures & Hardware Sensor Interface
// -----------------------------------------------------------------------------
typedef struct {
    uint8_t  major;
    uint8_t  minor;
    uint8_t  build;
    uint8_t  reserved;
    uint16_t release;
} SMCKeyData_vers_t;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t  dataAttributes;
} SMCKeyData_keyInfo_t;

typedef struct {
    uint32_t                  key;
    SMCKeyData_vers_t         vers;
    SMCKeyData_pLimitData_t   pLimitData;
    SMCKeyData_keyInfo_t      keyInfo;
    uint8_t                   result;
    uint8_t                   status;
    uint8_t                   data8;
    uint32_t                  data32;
    uint8_t                   bytes[32];
} SMCKeyData_t;

static io_connect_t g_smc_conn = 0;

static int smc_init(void) {
    if (g_smc_conn != 0) return 0;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return -1;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &g_smc_conn);
    IOObjectRelease(service);
    return (kr == kIOReturnSuccess) ? 0 : -2;
}

static float smc_read_key(const char *key_str) {
    if (smc_init() != 0 || !key_str || strlen(key_str) < 4) return -1.0f;
    uint32_t key32 = 0;
    memcpy(&key32, key_str, 4);
    key32 = __builtin_bswap32(key32);

    SMCKeyData_t in = {0}, out = {0};
    in.key = key32;
    in.data8 = 9; // READ_KEYINFO
    size_t s = sizeof(SMCKeyData_t);
    if (IOConnectCallStructMethod(g_smc_conn, 2, &in, s, &out, &s) != 0 || out.result != 0) {
        return -1.0f;
    }

    uint32_t size = out.keyInfo.dataSize;
    uint32_t type = __builtin_bswap32(out.keyInfo.dataType);
    char type_str[5] = {0};
    memcpy(type_str, &type, 4);

    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = key32;
    in.keyInfo.dataSize = size;
    in.data8 = 5; // READ_VALUE
    s = sizeof(SMCKeyData_t);
    if (IOConnectCallStructMethod(g_smc_conn, 2, &in, s, &out, &s) != 0 || out.result != 0) {
        return -1.0f;
    }

    int16_t raw16 = (int16_t)(out.bytes[0] << 8 | out.bytes[1]);
    uint16_t uraw16 = (uint16_t)(out.bytes[0] << 8 | out.bytes[1]);

    if (strcmp(type_str, "sp78") == 0 && size == 2) {
        return raw16 / 256.0f;
    } else if (strcmp(type_str, "fpe2") == 0 && size == 2) {
        return uraw16 / 4.0f;
    } else if (strcmp(type_str, "sp96") == 0 && size == 2) {
        return raw16 / 64.0f;
    } else if (strcmp(type_str, "sp3c") == 0 && size == 2) {
        return raw16 / 4096.0f;
    } else if (strcmp(type_str, "sp4b") == 0 && size == 2) {
        return raw16 / 2048.0f;
    } else if (strcmp(type_str, "sp5a") == 0 && size == 2) {
        return raw16 / 1024.0f;
    } else if (strcmp(type_str, "ui8 ") == 0 && size == 1) {
        return (float)out.bytes[0];
    } else if (strcmp(type_str, "ui16") == 0 && size == 2) {
        return (float)uraw16;
    }
    return -1.0f;
}

// -----------------------------------------------------------------------------
// UI Helper: Modern Dark Card View
// -----------------------------------------------------------------------------
@interface CardView : NSView
@property (nonatomic, strong) NSColor *borderColor;
@property (nonatomic, assign) CGFloat cornerRadius;
@end

@implementation CardView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _borderColor = [NSColor colorWithCalibratedRed:0.20 green:0.22 blue:0.32 alpha:0.75];
        _cornerRadius = 10.0;
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSRect b = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:b xRadius:_cornerRadius yRadius:_cornerRadius];
    [[NSColor colorWithCalibratedRed:0.10 green:0.11 blue:0.17 alpha:0.95] setFill];
    [path fill];
    [_borderColor setStroke];
    [path setLineWidth:1.0];
    [path stroke];
}
@end

// -----------------------------------------------------------------------------
// UI Helper: Animated Colored Progress Bar View
// -----------------------------------------------------------------------------
@interface ModernBarView : NSView
@property (nonatomic, assign) CGFloat progress;
@property (nonatomic, strong) NSColor *fillColor;
@property (nonatomic, strong) NSColor *trackColor;
@end

@implementation ModernBarView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _progress = 0.0;
        _fillColor = [NSColor colorWithCalibratedRed:0.22 green:0.74 blue:0.97 alpha:1.0];
        _trackColor = [NSColor colorWithCalibratedRed:0.16 green:0.18 blue:0.26 alpha:0.8];
    }
    return self;
}

- (void)setProgress:(CGFloat)progress {
    _progress = fmax(0.0, fmin(1.0, progress));
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSRect bounds = self.bounds;
    CGFloat r = bounds.size.height / 2.0;
    NSBezierPath *track = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:r yRadius:r];
    [_trackColor setFill];
    [track fill];

    if (_progress > 0.01) {
        NSRect fillRect = bounds;
        fillRect.size.width = fmax(bounds.size.height, bounds.size.width * _progress);
        NSBezierPath *fill = [NSBezierPath bezierPathWithRoundedRect:fillRect xRadius:r yRadius:r];
        [_fillColor setFill];
        [fill fill];
    }
}
@end

// -----------------------------------------------------------------------------
// UI Helper: Multi-Channel Real-time Waveform Graph
// -----------------------------------------------------------------------------
@interface SparklineGraphView : NSView {
    float _cpuHistory[GRAPH_CAPACITY];
    float _gpuHistory[GRAPH_CAPACITY];
    float _ramHistory[GRAPH_CAPACITY];
    float _tempHistory[GRAPH_CAPACITY];
    int _count;
}
- (void)addCPU:(float)cpu gpu:(float)gpu ram:(float)ram temp:(float)temp;
@end

@implementation SparklineGraphView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        memset(_cpuHistory, 0, sizeof(_cpuHistory));
        memset(_gpuHistory, 0, sizeof(_gpuHistory));
        memset(_ramHistory, 0, sizeof(_ramHistory));
        memset(_tempHistory, 0, sizeof(_tempHistory));
        _count = 0;
    }
    return self;
}

- (void)addCPU:(float)cpu gpu:(float)gpu ram:(float)ram temp:(float)temp {
    if (_count < GRAPH_CAPACITY) {
        _cpuHistory[_count] = cpu;
        _gpuHistory[_count] = gpu;
        _ramHistory[_count] = ram;
        _tempHistory[_count] = temp;
        _count++;
    } else {
        memmove(&_cpuHistory[0], &_cpuHistory[1], (GRAPH_CAPACITY - 1) * sizeof(float));
        memmove(&_gpuHistory[0], &_gpuHistory[1], (GRAPH_CAPACITY - 1) * sizeof(float));
        memmove(&_ramHistory[0], &_ramHistory[1], (GRAPH_CAPACITY - 1) * sizeof(float));
        memmove(&_tempHistory[0], &_tempHistory[1], (GRAPH_CAPACITY - 1) * sizeof(float));
        _cpuHistory[GRAPH_CAPACITY - 1] = cpu;
        _gpuHistory[GRAPH_CAPACITY - 1] = gpu;
        _ramHistory[GRAPH_CAPACITY - 1] = ram;
        _tempHistory[GRAPH_CAPACITY - 1] = temp;
    }
    [self setNeedsDisplay:YES];
}

- (void)drawLineForData:(float *)data maxVal:(float)maxVal color:(NSColor *)color inRect:(NSRect)rect {
    if (_count < 2) return;
    CGFloat stepX = rect.size.width / (GRAPH_CAPACITY - 1);
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path setLineWidth:1.8];
    [path setLineJoinStyle:NSLineJoinStyleRound];

    int offset = GRAPH_CAPACITY - _count;
    for (int i = 0; i < _count; i++) {
        CGFloat x = rect.origin.x + (offset + i) * stepX;
        float norm = fmax(0.0f, fmin(1.0f, data[i] / maxVal));
        CGFloat y = rect.origin.y + norm * (rect.size.height - 4) + 2;
        if (i == 0) {
            [path moveToPoint:NSMakePoint(x, y)];
        } else {
            [path lineToPoint:NSMakePoint(x, y)];
        }
    }
    [color setStroke];
    [path stroke];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSRect bounds = NSInsetRect(self.bounds, 2, 2);
    
    NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:8 yRadius:8];
    [[NSColor colorWithCalibratedRed:0.07 green:0.08 blue:0.13 alpha:0.95] setFill];
    [bg fill];
    [[NSColor colorWithCalibratedRed:0.20 green:0.22 blue:0.32 alpha:0.4] setStroke];
    [bg setLineWidth:1.0];
    [bg stroke];

    [[NSColor colorWithCalibratedRed:0.18 green:0.20 blue:0.28 alpha:0.4] setStroke];
    NSBezierPath *grid = [NSBezierPath bezierPath];
    [grid setLineWidth:0.8];
    for (int p = 1; p <= 3; p++) {
        CGFloat y = bounds.origin.y + (bounds.size.height * p / 4.0);
        [grid moveToPoint:NSMakePoint(bounds.origin.x + 8, y)];
        [grid lineToPoint:NSMakePoint(bounds.origin.x + bounds.size.width - 8, y)];
    }
    CGFloat dash[2] = {4.0, 4.0};
    [grid setLineDash:dash count:2 phase:0];
    [grid stroke];

    NSRect plotRect = NSInsetRect(bounds, 10, 8);
    [self drawLineForData:_ramHistory maxVal:100.0f color:[NSColor colorWithCalibratedRed:0.92 green:0.28 blue:0.60 alpha:0.85] inRect:plotRect]; // Pink RAM
    [self drawLineForData:_gpuHistory maxVal:100.0f color:[NSColor colorWithCalibratedRed:0.66 green:0.33 blue:0.97 alpha:0.85] inRect:plotRect]; // Purple GPU
    [self drawLineForData:_cpuHistory maxVal:100.0f color:[NSColor colorWithCalibratedRed:0.22 green:0.74 blue:0.97 alpha:0.95] inRect:plotRect]; // Cyan CPU
    [self drawLineForData:_tempHistory maxVal:100.0f color:[NSColor colorWithCalibratedRed:0.98 green:0.45 blue:0.18 alpha:0.95] inRect:plotRect]; // Orange Temp
}
@end

// -----------------------------------------------------------------------------
// UI Helper: Core Temp Detail Row (Core #, Current, Min, Max, TjMax, Load Bar)
// -----------------------------------------------------------------------------
@interface CoreTempRowView : NSView
@property (nonatomic, strong) NSTextField *coreNameLabel;
@property (nonatomic, strong) NSTextField *tempCurLabel;
@property (nonatomic, strong) NSTextField *tempMinLabel;
@property (nonatomic, strong) NSTextField *tempMaxLabel;
@property (nonatomic, strong) NSTextField *distTjMaxLabel;
@property (nonatomic, strong) ModernBarView *loadBar;
@property (nonatomic, strong) NSTextField *loadPctLabel;
@end

@implementation CoreTempRowView
- (instancetype)initWithFrame:(NSRect)frameRect coreTitle:(NSString *)title {
    self = [super initWithFrame:frameRect];
    if (self) {
        CGFloat h = frameRect.size.height;
        
        _coreNameLabel = [NSTextField labelWithString:title];
        _coreNameLabel.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightBold];
        _coreNameLabel.textColor = [NSColor colorWithCalibratedWhite:0.9 alpha:1.0];
        _coreNameLabel.frame = NSMakeRect(8, (h - 16) / 2.0, 95, 16);
        [self addSubview:_coreNameLabel];

        // Current Temp
        _tempCurLabel = [NSTextField labelWithString:@"-- °C"];
        _tempCurLabel.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightBold];
        _tempCurLabel.textColor = [NSColor colorWithCalibratedRed:0.98 green:0.55 blue:0.20 alpha:1.0];
        _tempCurLabel.alignment = NSTextAlignmentRight;
        _tempCurLabel.frame = NSMakeRect(105, (h - 16) / 2.0, 65, 16);
        [self addSubview:_tempCurLabel];

        // Min Temp
        _tempMinLabel = [NSTextField labelWithString:@"-- °C"];
        _tempMinLabel.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightRegular];
        _tempMinLabel.textColor = [NSColor colorWithCalibratedRed:0.35 green:0.75 blue:0.95 alpha:1.0];
        _tempMinLabel.alignment = NSTextAlignmentRight;
        _tempMinLabel.frame = NSMakeRect(175, (h - 16) / 2.0, 65, 16);
        [self addSubview:_tempMinLabel];

        // Max Temp
        _tempMaxLabel = [NSTextField labelWithString:@"-- °C"];
        _tempMaxLabel.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightRegular];
        _tempMaxLabel.textColor = [NSColor colorWithCalibratedRed:0.95 green:0.35 blue:0.35 alpha:1.0];
        _tempMaxLabel.alignment = NSTextAlignmentRight;
        _tempMaxLabel.frame = NSMakeRect(245, (h - 16) / 2.0, 65, 16);
        [self addSubview:_tempMaxLabel];

        // Distance to TjMax
        _distTjMaxLabel = [NSTextField labelWithString:@"-- °C"];
        _distTjMaxLabel.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightMedium];
        _distTjMaxLabel.textColor = [NSColor colorWithCalibratedRed:0.30 green:0.85 blue:0.55 alpha:1.0];
        _distTjMaxLabel.alignment = NSTextAlignmentRight;
        _distTjMaxLabel.frame = NSMakeRect(315, (h - 16) / 2.0, 75, 16);
        [self addSubview:_distTjMaxLabel];

        // Load Bar
        CGFloat barX = 400;
        CGFloat barW = frameRect.size.width - barX - 55;
        _loadBar = [[ModernBarView alloc] initWithFrame:NSMakeRect(barX, (h - 8) / 2.0, barW, 8)];
        [self addSubview:_loadBar];

        // Load %
        _loadPctLabel = [NSTextField labelWithString:@"0%"];
        _loadPctLabel.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightBold];
        _loadPctLabel.textColor = [NSColor colorWithCalibratedWhite:0.85 alpha:1.0];
        _loadPctLabel.alignment = NSTextAlignmentRight;
        _loadPctLabel.frame = NSMakeRect(frameRect.size.width - 50, (h - 16) / 2.0, 45, 16);
        [self addSubview:_loadPctLabel];
    }
    return self;
}

- (void)updateWithCur:(float)cur min:(float)min max:(float)max loadPct:(float)load {
    if (cur > 0) {
        _tempCurLabel.stringValue = [NSString stringWithFormat:@"%.1f °C", cur];
        _tempMinLabel.stringValue = [NSString stringWithFormat:@"%.1f °C", min];
        _tempMaxLabel.stringValue = [NSString stringWithFormat:@"%.1f °C", max];
        float dist = TJ_MAX - cur;
        _distTjMaxLabel.stringValue = [NSString stringWithFormat:@"%.1f °C", dist > 0 ? dist : 0];
        if (dist < 15.0f) {
            _distTjMaxLabel.textColor = [NSColor colorWithCalibratedRed:0.95 green:0.25 blue:0.25 alpha:1.0];
        } else if (dist < 30.0f) {
            _distTjMaxLabel.textColor = [NSColor colorWithCalibratedRed:0.95 green:0.65 blue:0.20 alpha:1.0];
        } else {
            _distTjMaxLabel.textColor = [NSColor colorWithCalibratedRed:0.30 green:0.85 blue:0.55 alpha:1.0];
        }
    }
    _loadPctLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", load];
    [_loadBar setProgress:load / 100.0];
    if (load > 80.0) {
        _loadBar.fillColor = [NSColor colorWithCalibratedRed:0.95 green:0.26 blue:0.26 alpha:1.0];
    } else if (load > 50.0) {
        _loadBar.fillColor = [NSColor colorWithCalibratedRed:0.95 green:0.65 blue:0.20 alpha:1.0];
    } else {
        _loadBar.fillColor = [NSColor colorWithCalibratedRed:0.22 green:0.74 blue:0.97 alpha:1.0];
    }
}
@end

// -----------------------------------------------------------------------------
// App Controller / Main Window
// -----------------------------------------------------------------------------
@interface SysPulseAppDelegate : NSObject <NSApplicationDelegate> {
    NSWindow *_window;
    NSTimer *_timer;
    NSTimeInterval _interval;

    // Menu Bar Extra (Status Item)
    NSStatusItem *_statusItem;

    // Core Temp Min/Max Tracking
    float _minCoreTemps[4];
    float _maxCoreTemps[4];
    float _minPkgTemp;
    float _maxPkgTemp;
    BOOL _hasSampledTemps;

    // CSV Logging
    BOOL _isLogging;
    NSFileHandle *_logFileHandle;
    NSUInteger _logRowCount;
    NSButton *_logButton;
    NSTextField *_logStatusLabel;

    // Overheat Alert
    NSTextField *_alertBanner;

    // Previous CPU tick state
    processor_info_array_t _prevCpuInfo;
    mach_msg_type_number_t _prevNumCpuInfo;
    natural_t _numCPUs;

    // Network delta calculation
    uint64_t _prevNetRx;
    uint64_t _prevNetTx;
    NSTimeInterval _prevNetTime;

    // UI Outlets
    NSTextField *_vpnBadge;
    NSSegmentedControl *_intervalControl;

    // Processor Specs Box
    NSTextField *_procPowerLabel;
    NSTextField *_procCorePowerLabel;
    NSTextField *_procGtPowerLabel;
    NSTextField *_procVoltageLabel;
    NSTextField *_procFrequencyLabel;
    NSTextField *_procTdpLabel;

    // Top Cards
    NSTextField *_cpuValLabel;
    ModernBarView *_cpuBar;
    NSTextField *_tempValLabel;
    NSTextField *_tempBadge;
    NSTextField *_gpuValLabel;
    ModernBarView *_gpuBar;
    NSTextField *_gpuSubLabel;
    NSTextField *_ramValLabel;
    ModernBarView *_ramBar;
    NSTextField *_ramSubLabel;

    // Core Temp Rows
    CoreTempRowView *_coreRows[4];
    CoreTempRowView *_pkgRow;

    // History Graph
    SparklineGraphView *_graphView;

    // Bottom Status
    NSTextField *_diskLabel;
    NSTextField *_netLabel;
    NSTextField *_batteryLabel;
}
@end

@implementation SysPulseAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    _interval = 1.0;
    _prevCpuInfo = NULL;
    _prevNumCpuInfo = 0;
    _numCPUs = 0;
    _prevNetRx = 0;
    _prevNetTx = 0;
    _prevNetTime = [NSDate timeIntervalSinceReferenceDate];
    _hasSampledTemps = NO;
    _isLogging = NO;
    _logRowCount = 0;

    for (int i = 0; i < 4; i++) {
        _minCoreTemps[i] = 999.0f;
        _maxCoreTemps[i] = -999.0f;
    }
    _minPkgTemp = 999.0f;
    _maxPkgTemp = -999.0f;

    [self setupMenuBarStatusItem];
    [self setupWindowAndUI];
    [self startTimer];
    [self updateMetrics];
}

// ---------------- Menu Bar Status Item (Core Temp Extra) ----------------
- (void)setupMenuBarStatusItem {
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.button.title = @"⚡ --°C";

    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"SysPulse — Core Temp Monitor" action:nil keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    
    NSMenuItem *showItem = [[NSMenuItem alloc] initWithTitle:@"Show Main Window" action:@selector(showMainWindow:) keyEquivalent:@"s"];
    [showItem setTarget:self];
    [menu addItem:showItem];

    NSMenuItem *resetItem = [[NSMenuItem alloc] initWithTitle:@"Reset Min / Max Temperatures" action:@selector(resetMinMaxTemps:) keyEquivalent:@"r"];
    [resetItem setTarget:self];
    [menu addItem:resetItem];

    NSMenuItem *fbItem = [[NSMenuItem alloc] initWithTitle:@"Send Feedback / Report Issue..." action:@selector(openFeedback:) keyEquivalent:@"f"];
    [fbItem setTarget:self];
    [menu addItem:fbItem];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit SysPulse" action:@selector(terminate:) keyEquivalent:@"q"];

    _statusItem.menu = menu;
}

- (void)showMainWindow:(id)sender {
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)resetMinMaxTemps:(id)sender {
    for (int i = 0; i < 4; i++) {
        _minCoreTemps[i] = 999.0f;
        _maxCoreTemps[i] = -999.0f;
    }
    _minPkgTemp = 999.0f;
    _maxPkgTemp = -999.0f;
    _hasSampledTemps = NO;
    [self updateMetrics];
}

// ---------------- CSV Logging Action ----------------
- (void)toggleLogging:(id)sender {
    if (!_isLogging) {
        NSString *path = [@"~/Desktop/SysPulse_CoreTemp_Log.csv" stringByExpandingTildeInPath];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            NSString *header = @"Timestamp,CPU_Overall_Pct,Pkg_Temp_C,Core1_Temp_C,Core2_Temp_C,Core3_Temp_C,Core4_Temp_C,Pkg_Power_W,Core_Voltage_V\n";
            [header writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        _logFileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
        [_logFileHandle seekToEndOfFile];
        _isLogging = YES;
        _logRowCount = 0;
        _logButton.title = @"Stop CSV Logging";
        _logStatusLabel.stringValue = @"● Recording to Desktop/SysPulse_CoreTemp_Log.csv";
        _logStatusLabel.textColor = [NSColor colorWithCalibratedRed:0.95 green:0.35 blue:0.35 alpha:1.0];
    } else {
        _isLogging = NO;
        if (_logFileHandle) {
            [_logFileHandle closeFile];
            _logFileHandle = nil;
        }
        _logButton.title = @"Start CSV Logging";
        _logStatusLabel.stringValue = [NSString stringWithFormat:@"Saved %lu entries to Desktop", (unsigned long)_logRowCount];
        _logStatusLabel.textColor = [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];
    }
}

// ---------------- Main Window Setup ----------------
- (void)setupWindowAndUI {
    NSRect frame = NSMakeRect(100, 60, 900, 780);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    _window = [[NSWindow alloc] initWithContentRect:frame styleMask:style backing:NSBackingStoreBuffered defer:NO];
    _window.title = @"SysPulse — Advanced Hardware & Core Temp Monitor";
    _window.minSize = NSMakeSize(860, 740);
    _window.backgroundColor = [NSColor colorWithCalibratedRed:0.07 green:0.08 blue:0.12 alpha:1.0];
    [_window center];

    NSView *root = _window.contentView;

    // Header Bar
    NSImageView *iconImg = [[NSImageView alloc] initWithFrame:NSMakeRect(20, frame.size.height - 58, 40, 40)];
    NSImage *appIcon = [NSApp applicationIconImage];
    if (appIcon) iconImg.image = appIcon;
    [root addSubview:iconImg];

    NSTextField *titleLabel = [NSTextField labelWithString:@"SysPulse"];
    titleLabel.font = [NSFont systemFontOfSize:18.0 weight:NSFontWeightBold];
    titleLabel.textColor = [NSColor colorWithCalibratedRed:0.35 green:0.85 blue:1.0 alpha:1.0];
    titleLabel.frame = NSMakeRect(68, frame.size.height - 43, 120, 24);
    [root addSubview:titleLabel];

    NSTextField *subLabel = [NSTextField labelWithString:@"Intel® Core™ i5-8350U (4C / 8T) • Kaby Lake-R • macOS"];
    subLabel.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular];
    subLabel.textColor = [NSColor colorWithCalibratedWhite:0.65 alpha:1.0];
    subLabel.frame = NSMakeRect(68, frame.size.height - 60, 360, 16);
    [root addSubview:subLabel];

    // VPN Badge
    _vpnBadge = [NSTextField labelWithString:@"● WireGuard: Checking..."];
    _vpnBadge.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium];
    _vpnBadge.textColor = [NSColor colorWithCalibratedRed:0.25 green:0.85 blue:0.55 alpha:1.0];
    _vpnBadge.alignment = NSTextAlignmentRight;
    _vpnBadge.frame = NSMakeRect(frame.size.width - 480, frame.size.height - 45, 290, 18);
    [root addSubview:_vpnBadge];

    // VPN Badge
    _vpnBadge.frame = NSMakeRect(frame.size.width - 550, frame.size.height - 45, 240, 18);

    // Interval Control
    _intervalControl = [NSSegmentedControl segmentedControlWithLabels:@[@"0.5s", @"1.0s", @"2.0s"]
                                                         trackingMode:NSSegmentSwitchTrackingSelectOne
                                                               target:self
                                                               action:@selector(intervalChanged:)];
    _intervalControl.selectedSegment = 1;
    _intervalControl.frame = NSMakeRect(frame.size.width - 295, frame.size.height - 47, 135, 24);
    [root addSubview:_intervalControl];

    // Feedback / Report Button
    NSButton *feedbackBtn = [NSButton buttonWithTitle:@"Feedback / Report" target:self action:@selector(openFeedback:)];
    feedbackBtn.bezelStyle = NSBezelStyleRounded;
    feedbackBtn.controlSize = NSControlSizeRegular;
    feedbackBtn.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium];
    feedbackBtn.frame = NSMakeRect(frame.size.width - 150, frame.size.height - 48, 130, 26);
    [root addSubview:feedbackBtn];

    // ---------------- Section 1: Processor Info & Electrical Strip ----------------
    CGFloat procY = frame.size.height - 128;
    CardView *procCard = [[CardView alloc] initWithFrame:NSMakeRect(20, procY, frame.size.width - 40, 60)];
    [root addSubview:procCard];

    NSTextField *procName = [NSTextField labelWithString:@"Processor: Intel Core i5-8350U  |  Codename: Kaby Lake-R (14nm)  |  Socket: FCBGA1356  |  Cores: 4 (8 Threads)"];
    procName.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium];
    procName.textColor = [NSColor colorWithCalibratedWhite:0.85 alpha:1.0];
    procName.frame = NSMakeRect(12, 34, procCard.bounds.size.width - 24, 16);
    [procCard addSubview:procName];

    _procPowerLabel = [NSTextField labelWithString:@"Pkg: -- W"];
    _procPowerLabel.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightBold];
    _procPowerLabel.textColor = [NSColor colorWithCalibratedRed:0.95 green:0.75 blue:0.20 alpha:1.0];
    _procPowerLabel.frame = NSMakeRect(12, 10, 115, 16);
    [procCard addSubview:_procPowerLabel];

    _procCorePowerLabel = [NSTextField labelWithString:@"Core Pwr: -- W"];
    _procCorePowerLabel.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightBold];
    _procCorePowerLabel.textColor = [NSColor colorWithCalibratedRed:0.98 green:0.55 blue:0.25 alpha:1.0];
    _procCorePowerLabel.frame = NSMakeRect(130, 10, 135, 16);
    [procCard addSubview:_procCorePowerLabel];

    _procGtPowerLabel = [NSTextField labelWithString:@"GT Pwr: -- W"];
    _procGtPowerLabel.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightBold];
    _procGtPowerLabel.textColor = [NSColor colorWithCalibratedRed:0.75 green:0.45 blue:1.0 alpha:1.0];
    _procGtPowerLabel.frame = NSMakeRect(270, 10, 125, 16);
    [procCard addSubview:_procGtPowerLabel];

    _procVoltageLabel = [NSTextField labelWithString:@"VID: -- V"];
    _procVoltageLabel.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightBold];
    _procVoltageLabel.textColor = [NSColor colorWithCalibratedRed:0.35 green:0.85 blue:1.0 alpha:1.0];
    _procVoltageLabel.frame = NSMakeRect(400, 10, 110, 16);
    [procCard addSubview:_procVoltageLabel];

    _procFrequencyLabel = [NSTextField labelWithString:@"Clock: 1.70 - 3.60 GHz"];
    _procFrequencyLabel.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightRegular];
    _procFrequencyLabel.textColor = [NSColor colorWithCalibratedWhite:0.75 alpha:1.0];
    _procFrequencyLabel.frame = NSMakeRect(515, 10, 180, 16);
    [procCard addSubview:_procFrequencyLabel];

    _procTdpLabel = [NSTextField labelWithString:@"TDP: 15.0 W"];
    _procTdpLabel.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular];
    _procTdpLabel.textColor = [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];
    _procTdpLabel.frame = NSMakeRect(procCard.bounds.size.width - 110, 10, 100, 16);
    [procCard addSubview:_procTdpLabel];

    // ---------------- Section 2: 4 Top Metric Cards ----------------
    CGFloat cardY = procY - 110;
    CGFloat cardH = 98;
    CGFloat cardSpacing = 12;
    CGFloat cardW = (frame.size.width - 40 - (3 * cardSpacing)) / 4.0;

    // Card 1: Overall CPU
    CardView *c1 = [[CardView alloc] initWithFrame:NSMakeRect(20 + 0 * (cardW + cardSpacing), cardY, cardW, cardH)];
    [root addSubview:c1];
    NSTextField *t1 = [NSTextField labelWithString:@"TOTAL CPU LOAD"];
    t1.font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightBold];
    t1.textColor = [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];
    t1.frame = NSMakeRect(12, cardH - 22, cardW - 24, 14);
    [c1 addSubview:t1];
    _cpuValLabel = [NSTextField labelWithString:@"0%"];
    _cpuValLabel.font = [NSFont monospacedDigitSystemFontOfSize:24.0 weight:NSFontWeightBold];
    _cpuValLabel.textColor = [NSColor colorWithCalibratedRed:0.22 green:0.74 blue:0.97 alpha:1.0];
    _cpuValLabel.frame = NSMakeRect(12, cardH - 52, cardW - 24, 28);
    [c1 addSubview:_cpuValLabel];
    _cpuBar = [[ModernBarView alloc] initWithFrame:NSMakeRect(12, 14, cardW - 24, 6)];
    [c1 addSubview:_cpuBar];

    // Card 2: Package Temp
    CardView *c2 = [[CardView alloc] initWithFrame:NSMakeRect(20 + 1 * (cardW + cardSpacing), cardY, cardW, cardH)];
    [root addSubview:c2];
    NSTextField *t2 = [NSTextField labelWithString:@"PACKAGE TEMPERATURE"];
    t2.font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightBold];
    t2.textColor = [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];
    t2.frame = NSMakeRect(12, cardH - 22, cardW - 24, 14);
    [c2 addSubview:t2];
    _tempValLabel = [NSTextField labelWithString:@"-- °C"];
    _tempValLabel.font = [NSFont monospacedDigitSystemFontOfSize:24.0 weight:NSFontWeightBold];
    _tempValLabel.textColor = [NSColor colorWithCalibratedRed:0.98 green:0.45 blue:0.18 alpha:1.0];
    _tempValLabel.frame = NSMakeRect(12, cardH - 52, cardW - 24, 28);
    [c2 addSubview:_tempValLabel];
    _tempBadge = [NSTextField labelWithString:@"OPTIMAL"];
    _tempBadge.font = [NSFont systemFontOfSize:9.0 weight:NSFontWeightBold];
    _tempBadge.textColor = [NSColor colorWithCalibratedRed:0.2 green:0.85 blue:0.5 alpha:1.0];
    _tempBadge.frame = NSMakeRect(12, 12, cardW - 24, 14);
    [c2 addSubview:_tempBadge];

    // Card 3: GPU
    CardView *c3 = [[CardView alloc] initWithFrame:NSMakeRect(20 + 2 * (cardW + cardSpacing), cardY, cardW, cardH)];
    [root addSubview:c3];
    NSTextField *t3 = [NSTextField labelWithString:@"GPU (INTEL UHD 620)"];
    t3.font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightBold];
    t3.textColor = [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];
    t3.frame = NSMakeRect(12, cardH - 22, cardW - 24, 14);
    [c3 addSubview:t3];
    _gpuValLabel = [NSTextField labelWithString:@"0%"];
    _gpuValLabel.font = [NSFont monospacedDigitSystemFontOfSize:24.0 weight:NSFontWeightBold];
    _gpuValLabel.textColor = [NSColor colorWithCalibratedRed:0.66 green:0.33 blue:0.97 alpha:1.0];
    _gpuValLabel.frame = NSMakeRect(12, cardH - 52, cardW - 24, 28);
    [c3 addSubview:_gpuValLabel];
    _gpuBar = [[ModernBarView alloc] initWithFrame:NSMakeRect(12, 24, cardW - 24, 6)];
    _gpuBar.fillColor = [NSColor colorWithCalibratedRed:0.66 green:0.33 blue:0.97 alpha:1.0];
    [c3 addSubview:_gpuBar];
    _gpuSubLabel = [NSTextField labelWithString:@"Clock: -- MHz • GT: -- W"];
    _gpuSubLabel.font = [NSFont monospacedDigitSystemFontOfSize:9.0 weight:NSFontWeightMedium];
    _gpuSubLabel.textColor = [NSColor colorWithCalibratedWhite:0.75 alpha:1.0];
    _gpuSubLabel.frame = NSMakeRect(12, 6, cardW - 24, 14);
    [c3 addSubview:_gpuSubLabel];

    // Card 4: RAM
    CardView *c4 = [[CardView alloc] initWithFrame:NSMakeRect(20 + 3 * (cardW + cardSpacing), cardY, cardW, cardH)];
    [root addSubview:c4];
    NSTextField *t4 = [NSTextField labelWithString:@"MEMORY (RAM)"];
    t4.font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightBold];
    t4.textColor = [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];
    t4.frame = NSMakeRect(12, cardH - 22, cardW - 24, 14);
    [c4 addSubview:t4];
    _ramValLabel = [NSTextField labelWithString:@"0%"];
    _ramValLabel.font = [NSFont monospacedDigitSystemFontOfSize:24.0 weight:NSFontWeightBold];
    _ramValLabel.textColor = [NSColor colorWithCalibratedRed:0.92 green:0.28 blue:0.60 alpha:1.0];
    _ramValLabel.frame = NSMakeRect(12, cardH - 52, cardW - 24, 28);
    [c4 addSubview:_ramValLabel];
    _ramBar = [[ModernBarView alloc] initWithFrame:NSMakeRect(12, 24, cardW - 24, 6)];
    _ramBar.fillColor = [NSColor colorWithCalibratedRed:0.92 green:0.28 blue:0.60 alpha:1.0];
    [c4 addSubview:_ramBar];
    _ramSubLabel = [NSTextField labelWithString:@"Used: -- GB / 8.0 GB"];
    _ramSubLabel.font = [NSFont systemFontOfSize:9.0 weight:NSFontWeightRegular];
    _ramSubLabel.textColor = [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];
    _ramSubLabel.frame = NSMakeRect(12, 6, cardW - 24, 14);
    [c4 addSubview:_ramSubLabel];

    // ---------------- Section 3: Core Temp Signature Table ----------------
    CGFloat tblY = cardY - 215;
    CGFloat tblH = 205;
    CardView *tblCard = [[CardView alloc] initWithFrame:NSMakeRect(20, tblY, frame.size.width - 40, tblH)];
    [root addSubview:tblCard];

    // Header with TjMax & Reset Button
    NSTextField *tblTitle = [NSTextField labelWithString:@"CORE TEMPERATURES & THERMAL HEADROOM (Tj. Max: 100.0 °C)"];
    tblTitle.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightBold];
    tblTitle.textColor = [NSColor colorWithCalibratedWhite:0.85 alpha:1.0];
    tblTitle.frame = NSMakeRect(12, tblH - 24, 500, 16);
    [tblCard addSubview:tblTitle];

    NSButton *resetBtn = [NSButton buttonWithTitle:@"Reset Min/Max" target:self action:@selector(resetMinMaxTemps:)];
    resetBtn.bezelStyle = NSBezelStyleRounded;
    resetBtn.controlSize = NSControlSizeSmall;
    resetBtn.font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightMedium];
    resetBtn.frame = NSMakeRect(tblCard.bounds.size.width - 120, tblH - 28, 110, 22);
    [tblCard addSubview:resetBtn];

    // Table Column Headers
    CGFloat colY = tblH - 46;
    NSTextField *ch0 = [NSTextField labelWithString:@"Core"]; ch0.frame = NSMakeRect(20, colY, 80, 14);
    NSTextField *ch1 = [NSTextField labelWithString:@"Current"]; ch1.frame = NSMakeRect(120, colY, 65, 14); ch1.alignment = NSTextAlignmentRight;
    NSTextField *ch2 = [NSTextField labelWithString:@"Min"]; ch2.frame = NSMakeRect(190, colY, 65, 14); ch2.alignment = NSTextAlignmentRight;
    NSTextField *ch3 = [NSTextField labelWithString:@"Max"]; ch3.frame = NSMakeRect(260, colY, 65, 14); ch3.alignment = NSTextAlignmentRight;
    NSTextField *ch4 = [NSTextField labelWithString:@"Dist to TjMax"]; ch4.frame = NSMakeRect(325, colY, 80, 14); ch4.alignment = NSTextAlignmentRight;
    NSTextField *ch5 = [NSTextField labelWithString:@"Load %"]; ch5.frame = NSMakeRect(420, colY, 80, 14);
    
    NSArray *headers = @[ch0, ch1, ch2, ch3, ch4, ch5];
    for (NSTextField *h in headers) {
        h.font = [NSFont systemFontOfSize:9.0 weight:NSFontWeightBold];
        h.textColor = [NSColor colorWithCalibratedWhite:0.5 alpha:1.0];
        [tblCard addSubview:h];
    }

    // 4 Core Rows + 1 Package Row
    CGFloat rowH = 28;
    for (int i = 0; i < 4; i++) {
        CGFloat ry = tblH - 74 - i * rowH;
        _coreRows[i] = [[CoreTempRowView alloc] initWithFrame:NSMakeRect(12, ry, tblCard.bounds.size.width - 24, rowH)
                                                    coreTitle:[NSString stringWithFormat:@"Core #%d", i]];
        [tblCard addSubview:_coreRows[i]];
    }

    // Package Row
    CGFloat pkgY = tblH - 74 - 4 * rowH;
    _pkgRow = [[CoreTempRowView alloc] initWithFrame:NSMakeRect(12, pkgY, tblCard.bounds.size.width - 24, rowH)
                                           coreTitle:@"CPU Package"];
    [tblCard addSubview:_pkgRow];

    // ---------------- Section 4: 60-Second History Graph ----------------
    CGFloat graphY = tblY - 170;
    CGFloat graphH = 160;
    CardView *graphContainer = [[CardView alloc] initWithFrame:NSMakeRect(20, graphY, frame.size.width - 40, graphH)];
    [root addSubview:graphContainer];

    NSTextField *graphTitle = [NSTextField labelWithString:@"REAL-TIME ACTIVITY HISTORY (LAST 60 SECONDS)"];
    graphTitle.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightBold];
    graphTitle.textColor = [NSColor colorWithCalibratedWhite:0.7 alpha:1.0];
    graphTitle.frame = NSMakeRect(14, graphH - 24, 350, 16);
    [graphContainer addSubview:graphTitle];

    NSTextField *legend = [NSTextField labelWithString:@"● CPU  ● GPU  ● RAM  ● Temp"];
    legend.font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightBold];
    legend.alignment = NSTextAlignmentRight;
    legend.frame = NSMakeRect(graphContainer.bounds.size.width - 240, graphH - 24, 226, 16);
    NSMutableAttributedString *attLegend = [[NSMutableAttributedString alloc] initWithString:@"● CPU  ● GPU  ● RAM  ● Temp"];
    [attLegend addAttribute:NSForegroundColorAttributeName value:[NSColor colorWithCalibratedRed:0.22 green:0.74 blue:0.97 alpha:1.0] range:[attLegend.string rangeOfString:@"● CPU"]];
    [attLegend addAttribute:NSForegroundColorAttributeName value:[NSColor colorWithCalibratedRed:0.66 green:0.33 blue:0.97 alpha:1.0] range:[attLegend.string rangeOfString:@"● GPU"]];
    [attLegend addAttribute:NSForegroundColorAttributeName value:[NSColor colorWithCalibratedRed:0.92 green:0.28 blue:0.60 alpha:1.0] range:[attLegend.string rangeOfString:@"● RAM"]];
    [attLegend addAttribute:NSForegroundColorAttributeName value:[NSColor colorWithCalibratedRed:0.98 green:0.45 blue:0.18 alpha:1.0] range:[attLegend.string rangeOfString:@"● Temp"]];
    legend.attributedStringValue = attLegend;
    [graphContainer addSubview:legend];

    _graphView = [[SparklineGraphView alloc] initWithFrame:NSMakeRect(14, 10, graphContainer.bounds.size.width - 28, graphH - 38)];
    [graphContainer addSubview:_graphView];

    // ---------------- Section 5: Bottom Tools & Logging Strip ----------------
    CGFloat botY = 14;
    CGFloat botH = 48;
    CGFloat botSpacing = 12;
    CGFloat botW = (frame.size.width - 40 - (2 * botSpacing)) / 3.0;

    // Disk
    CardView *dCard = [[CardView alloc] initWithFrame:NSMakeRect(20 + 0 * (botW + botSpacing), botY, botW, botH)];
    [root addSubview:dCard];
    NSTextField *dt = [NSTextField labelWithString:@"STORAGE (MACINTOSH HD)"];
    dt.font = [NSFont systemFontOfSize:9.0 weight:NSFontWeightBold];
    dt.textColor = [NSColor colorWithCalibratedWhite:0.55 alpha:1.0];
    dt.frame = NSMakeRect(10, botH - 18, botW - 20, 12);
    [dCard addSubview:dt];
    _diskLabel = [NSTextField labelWithString:@"Used: -- GB / -- GB (--)"];
    _diskLabel.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightMedium];
    _diskLabel.textColor = [NSColor colorWithCalibratedWhite:0.9 alpha:1.0];
    _diskLabel.frame = NSMakeRect(10, 8, botW - 20, 16);
    [dCard addSubview:_diskLabel];

    // Net
    CardView *nCard = [[CardView alloc] initWithFrame:NSMakeRect(20 + 1 * (botW + botSpacing), botY, botW, botH)];
    [root addSubview:nCard];
    NSTextField *nt = [NSTextField labelWithString:@"NETWORK REAL-TIME I/O"];
    nt.font = [NSFont systemFontOfSize:9.0 weight:NSFontWeightBold];
    nt.textColor = [NSColor colorWithCalibratedWhite:0.55 alpha:1.0];
    nt.frame = NSMakeRect(10, botH - 18, botW - 20, 12);
    [nCard addSubview:nt];
    _netLabel = [NSTextField labelWithString:@"↓ 0 KB/s   ↑ 0 KB/s"];
    _netLabel.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightMedium];
    _netLabel.textColor = [NSColor colorWithCalibratedRed:0.25 green:0.85 blue:0.55 alpha:1.0];
    _netLabel.frame = NSMakeRect(10, 8, botW - 20, 16);
    [nCard addSubview:_netLabel];

    // Logging & Tools Card
    CardView *lCard = [[CardView alloc] initWithFrame:NSMakeRect(20 + 2 * (botW + botSpacing), botY, botW, botH)];
    [root addSubview:lCard];
    
    _logButton = [NSButton buttonWithTitle:@"Start CSV Logging" target:self action:@selector(toggleLogging:)];
    _logButton.bezelStyle = NSBezelStyleRounded;
    _logButton.controlSize = NSControlSizeSmall;
    _logButton.font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightMedium];
    _logButton.frame = NSMakeRect(8, (botH - 22) / 2.0, 130, 22);
    [lCard addSubview:_logButton];

    _logStatusLabel = [NSTextField labelWithString:@"Ready to log to CSV"];
    _logStatusLabel.font = [NSFont systemFontOfSize:9.0 weight:NSFontWeightRegular];
    _logStatusLabel.textColor = [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];
    _logStatusLabel.frame = NSMakeRect(144, (botH - 14) / 2.0, botW - 150, 14);
    [lCard addSubview:_logStatusLabel];

    [_window makeKeyAndOrderFront:nil];
}

- (void)intervalChanged:(id)sender {
    switch (_intervalControl.selectedSegment) {
        case 0: _interval = 0.5; break;
        case 1: _interval = 1.0; break;
        case 2: _interval = 2.0; break;
        default: _interval = 1.0; break;
    }
    [self startTimer];
}

- (void)startTimer {
    if (_timer) {
        [_timer invalidate];
    }
    _timer = [NSTimer scheduledTimerWithTimeInterval:_interval
                                              target:self
                                            selector:@selector(updateMetrics)
                                            userInfo:nil
                                             repeats:YES];
}

- (void)updateMetrics {
    // 1. Mach CPU Ticks Calculation
    natural_t numCPUs = 0;
    processor_info_array_t cpuInfo = NULL;
    mach_msg_type_number_t numCpuInfo = 0;

    float overallCpu = 0.0f;
    float perCore[16] = {0};

    kern_return_t kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCpuInfo);
    if (kr == KERN_SUCCESS) {
        _numCPUs = numCPUs;
        if (_prevCpuInfo) {
            float totalUsage = 0.0f;
            for (natural_t i = 0; i < numCPUs && i < 16; i++) {
                int user = cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER] - _prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER];
                int sys  = cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM] - _prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM];
                int nice = cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE] - _prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE];
                int idle = cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE] - _prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE];
                int total = user + sys + nice + idle;
                float pct = (total > 0) ? ((float)(user + sys + nice) * 100.0f / total) : 0.0f;
                perCore[i] = pct;
                totalUsage += pct;
            }
            overallCpu = totalUsage / numCPUs;
            vm_deallocate(mach_task_self(), (vm_address_t)_prevCpuInfo, _prevNumCpuInfo * sizeof(integer_t));
        }
        _prevCpuInfo = cpuInfo;
        _prevNumCpuInfo = numCpuInfo;
    }

    _cpuValLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", overallCpu];
    [_cpuBar setProgress:overallCpu / 100.0];
    if (overallCpu > 80) {
        _cpuBar.fillColor = [NSColor colorWithCalibratedRed:0.95 green:0.25 blue:0.25 alpha:1.0];
    } else if (overallCpu > 50) {
        _cpuBar.fillColor = [NSColor colorWithCalibratedRed:0.95 green:0.65 blue:0.20 alpha:1.0];
    } else {
        _cpuBar.fillColor = [NSColor colorWithCalibratedRed:0.22 green:0.74 blue:0.97 alpha:1.0];
    }

    // 2. Core Temp Sensors (Package + Cores)
    float cpuTemp = smc_read_key("TC0D");
    if (cpuTemp <= 0) cpuTemp = smc_read_key("TC0P");
    if (cpuTemp <= 0) cpuTemp = smc_read_key("TC1C");

    float coreTemps[4] = {0};
    coreTemps[0] = smc_read_key("TC1C");
    coreTemps[1] = smc_read_key("TC2C");
    coreTemps[2] = smc_read_key("TC3C");
    coreTemps[3] = smc_read_key("TC4C");

    // Track Min and Max
    if (cpuTemp > 0) {
        if (!_hasSampledTemps) {
            _minPkgTemp = cpuTemp;
            _maxPkgTemp = cpuTemp;
            for (int i = 0; i < 4; i++) {
                _minCoreTemps[i] = coreTemps[i] > 0 ? coreTemps[i] : cpuTemp;
                _maxCoreTemps[i] = coreTemps[i] > 0 ? coreTemps[i] : cpuTemp;
            }
            _hasSampledTemps = YES;
        } else {
            if (cpuTemp < _minPkgTemp) _minPkgTemp = cpuTemp;
            if (cpuTemp > _maxPkgTemp) _maxPkgTemp = cpuTemp;
            for (int i = 0; i < 4; i++) {
                if (coreTemps[i] > 0) {
                    if (coreTemps[i] < _minCoreTemps[i]) _minCoreTemps[i] = coreTemps[i];
                    if (coreTemps[i] > _maxCoreTemps[i]) _maxCoreTemps[i] = coreTemps[i];
                }
            }
        }
    }

    // Update Status Bar Item (Menu Bar Extra)
    if (cpuTemp > 0) {
        _statusItem.button.title = [NSString stringWithFormat:@"⚡ %.0f°C", cpuTemp];
    }

    // Update Package Card
    if (cpuTemp > 0) {
        _tempValLabel.stringValue = [NSString stringWithFormat:@"%.1f °C", cpuTemp];
        if (cpuTemp > 85.0) {
            _tempBadge.stringValue = @"CRITICAL";
            _tempBadge.textColor = [NSColor colorWithCalibratedRed:0.95 green:0.2 blue:0.2 alpha:1.0];
        } else if (cpuTemp > 70.0) {
            _tempBadge.stringValue = @"WARM";
            _tempBadge.textColor = [NSColor colorWithCalibratedRed:0.95 green:0.65 blue:0.2 alpha:1.0];
        } else {
            _tempBadge.stringValue = @"OPTIMAL";
            _tempBadge.textColor = [NSColor colorWithCalibratedRed:0.2 green:0.85 blue:0.5 alpha:1.0];
        }
    }

    // Update Core Temp Rows
    for (int i = 0; i < 4; i++) {
        float avgCoreLoad = (perCore[i * 2] + perCore[i * 2 + 1]) / 2.0f;
        [_coreRows[i] updateWithCur:coreTemps[i] min:_minCoreTemps[i] max:_maxCoreTemps[i] loadPct:avgCoreLoad];
    }
    [_pkgRow updateWithCur:cpuTemp min:_minPkgTemp max:_maxPkgTemp loadPct:overallCpu];



    // 3. Electrical & Power Readings (Package, Core, GT Watts & VID Volts)
    float pkgPower = smc_read_key("PCPC");
    if (pkgPower <= 0) pkgPower = smc_read_key("PCPR");
    float corePower = smc_read_key("PC0C");
    if (corePower <= 0) corePower = smc_read_key("PC0R");
    float gtPower = smc_read_key("PCPG");
    if (gtPower < 0) gtPower = smc_read_key("PG0R");
    float vid = smc_read_key("VC0C");

    if (pkgPower > 0) _procPowerLabel.stringValue = [NSString stringWithFormat:@"Pkg: %.2f W", pkgPower];
    if (corePower > 0) _procCorePowerLabel.stringValue = [NSString stringWithFormat:@"Core Pwr: %.2f W", corePower];
    if (gtPower >= 0) _procGtPowerLabel.stringValue = [NSString stringWithFormat:@"GT Pwr: %.2f W", gtPower];
    if (vid > 0) _procVoltageLabel.stringValue = [NSString stringWithFormat:@"VID: %.3f V", vid];

    // 4. GPU (IOKit IntelAccelerator + Clock & GT Power)
    int gpuUtil = 0;
    int gpuUtilPState = 0;
    long long vramUsed = 0;
    io_service_t gpuService = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IntelAccelerator"));
    if (gpuService) {
        CFMutableDictionaryRef props = NULL;
        if (IORegistryEntryCreateCFProperties(gpuService, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS && props) {
            CFDictionaryRef perf = (CFDictionaryRef)CFDictionaryGetValue(props, CFSTR("PerformanceStatistics"));
            if (perf) {
                CFNumberRef u = (CFNumberRef)CFDictionaryGetValue(perf, CFSTR("Device Utilization %"));
                CFNumberRef up = (CFNumberRef)CFDictionaryGetValue(perf, CFSTR("Device Utilization % at cur p-state"));
                CFNumberRef v = (CFNumberRef)CFDictionaryGetValue(perf, CFSTR("gartUsedBytes"));
                if (u) CFNumberGetValue(u, kCFNumberIntType, &gpuUtil);
                if (up) CFNumberGetValue(up, kCFNumberIntType, &gpuUtilPState);
                if (v) CFNumberGetValue(v, kCFNumberLongLongType, &vramUsed);
            }
            CFRelease(props);
        }
        IOObjectRelease(gpuService);
    }
    
    // Calculate dynamic GPU frequency in MHz
    int gpuFreq = 300;
    if (gpuUtil > 0 && gpuUtilPState > 0) {
        float ratio = fminf(1.0f, fmaxf(0.26f, (float)gpuUtil / (float)gpuUtilPState));
        gpuFreq = (int)(ratio * 1150.0f);
    } else if (gpuUtil > 0) {
        gpuFreq = 300 + (int)((float)gpuUtil / 100.0f * 850.0f);
    }

    _gpuValLabel.stringValue = [NSString stringWithFormat:@"%d%%", gpuUtil];
    [_gpuBar setProgress:gpuUtil / 100.0];
    _gpuSubLabel.stringValue = [NSString stringWithFormat:@"%d MHz • GT: %.2f W", gpuFreq, gtPower >= 0 ? gtPower : 0.0f];

    // 5. RAM
    vm_size_t pageSize;
    host_page_size(mach_host_self(), &pageSize);
    vm_statistics64_data_t vmStats;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    float ramPct = 0.0f;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vmStats, &count) == KERN_SUCCESS) {
        uint64_t totalMem = 0;
        size_t len = sizeof(totalMem);
        sysctlbyname("hw.memsize", &totalMem, &len, NULL, 0);
        uint64_t usedBytes = ((uint64_t)(vmStats.active_count + vmStats.wire_count + vmStats.speculative_count)) * pageSize;
        ramPct = (usedBytes * 100.0f) / totalMem;
        _ramValLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", ramPct];
        [_ramBar setProgress:ramPct / 100.0];
        _ramSubLabel.stringValue = [NSString stringWithFormat:@"Used: %.2f GB / %.1f GB", usedBytes / (1024.0*1024.0*1024.0), totalMem / (1024.0*1024.0*1024.0)];
    }

    // 6. Waveform Graph
    [_graphView addCPU:overallCpu gpu:(float)gpuUtil ram:ramPct temp:(cpuTemp > 0 ? cpuTemp : 50.0f)];

    // 7. Disk Usage
    struct statfs sf;
    if (statfs("/", &sf) == 0) {
        uint64_t total = sf.f_blocks * sf.f_bsize;
        uint64_t avail = sf.f_bavail * sf.f_bsize;
        uint64_t used = total - avail;
        _diskLabel.stringValue = [NSString stringWithFormat:@"%.1f GB / %.1f GB (%.0f%% used)",
                                 used / (1024.0*1024.0*1024.0), total / (1024.0*1024.0*1024.0),
                                 (used * 100.0) / total];
    }

    // 8. Network Traffic
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval dt = now - _prevNetTime;
    struct ifaddrs *ifap = NULL;
    uint64_t curRx = 0, curTx = 0;
    if (getifaddrs(&ifap) == 0) {
        for (struct ifaddrs *ifa = ifap; ifa; ifa = ifa->ifa_next) {
            if ((ifa->ifa_flags & IFF_LOOPBACK) || !(ifa->ifa_flags & IFF_UP)) continue;
            if (ifa->ifa_data && ifa->ifa_addr && ifa->ifa_addr->sa_family == AF_LINK) {
                struct if_data *ifd = (struct if_data *)ifa->ifa_data;
                curRx += ifd->ifi_ibytes;
                curTx += ifd->ifi_obytes;
            }
        }
        freeifaddrs(ifap);
    }
    if (_prevNetRx > 0 && dt > 0.1) {
        double rxRate = (curRx >= _prevNetRx) ? (curRx - _prevNetRx) / dt : 0;
        double txRate = (curTx >= _prevNetTx) ? (curTx - _prevNetTx) / dt : 0;
        NSString *rxStr = (rxRate > 1024 * 1024) ? [NSString stringWithFormat:@"%.1f MB/s", rxRate / (1024*1024)] : [NSString stringWithFormat:@"%.0f KB/s", rxRate / 1024];
        NSString *txStr = (txRate > 1024 * 1024) ? [NSString stringWithFormat:@"%.1f MB/s", txRate / (1024*1024)] : [NSString stringWithFormat:@"%.0f KB/s", txRate / 1024];
        _netLabel.stringValue = [NSString stringWithFormat:@"↓ %@   ↑ %@", rxStr, txStr];
    }
    _prevNetRx = curRx;
    _prevNetTx = curTx;
    _prevNetTime = now;

    // 9. WireGuard Status
    BOOL wgActive = NO;
    struct ifaddrs *ifaList = NULL;
    if (getifaddrs(&ifaList) == 0) {
        for (struct ifaddrs *ifa = ifaList; ifa; ifa = ifa->ifa_next) {
            if ((ifa->ifa_flags & IFF_UP) && strncmp(ifa->ifa_name, "utun", 4) == 0) {
                if (ifa->ifa_addr && ifa->ifa_addr->sa_family == AF_INET) {
                    struct sockaddr_in *sin = (struct sockaddr_in *)ifa->ifa_addr;
                    char ip[INET_ADDRSTRLEN];
                    inet_ntop(AF_INET, &(sin->sin_addr), ip, INET_ADDRSTRLEN);
                    if (strncmp(ip, "10.250", 6) == 0 || strncmp(ip, "10.", 3) == 0) {
                        wgActive = YES;
                        _vpnBadge.stringValue = [NSString stringWithFormat:@"● WireGuard: CS302 (%s)", ip];
                        _vpnBadge.textColor = [NSColor colorWithCalibratedRed:0.25 green:0.85 blue:0.55 alpha:1.0];
                        break;
                    }
                }
            }
        }
        freeifaddrs(ifaList);
    }
    if (!wgActive) {
        _vpnBadge.stringValue = @"○ WireGuard: Disconnected";
        _vpnBadge.textColor = [NSColor colorWithCalibratedWhite:0.55 alpha:1.0];
    }

    // 10. Write to CSV Log if enabled
    if (_isLogging && _logFileHandle) {
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSString *ts = [df stringFromDate:[NSDate date]];
        NSString *row = [NSString stringWithFormat:@"%@,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.2f,%.3f\n",
                         ts, overallCpu, cpuTemp, coreTemps[0], coreTemps[1], coreTemps[2], coreTemps[3], pkgPower, vid];
        [_logFileHandle writeData:[row dataUsingEncoding:NSUTF8StringEncoding]];
        _logRowCount++;
        _logStatusLabel.stringValue = [NSString stringWithFormat:@"● Logged %lu records", (unsigned long)_logRowCount];
    }
}


- (void)openFeedback:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"SysPulse Feedback & GitHub Issue Reporter";
    alert.informativeText = @"Choose how to submit your feedback or diagnostic report:";
    [alert addButtonWithTitle:@"Send Report Automatically to GitHub"];
    [alert addButtonWithTitle:@"Copy Diagnostics to Clipboard"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *inputField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 24)];
    inputField.placeholderString = @"Optional: Brief note or issue description...";
    alert.accessoryView = inputField;

    NSModalResponse resp = [alert runModal];
    if (resp == NSAlertFirstButtonReturn) {
        NSString *userNote = inputField.stringValue;
        if (userNote.length == 0) userNote = @"Automated Hardware Diagnostics Report";
        
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSString *ts = [df stringFromDate:[NSDate date]];

        NSString *reportTitle = [NSString stringWithFormat:@"[Diagnostics] %@ - %@", userNote, ts];
        NSString *reportContent = [NSString stringWithFormat:
            @"## 📊 SysPulse Hardware Diagnostic Report\n"
            @"**Note / Description:** %@\n"
            @"**Timestamp:** %@\n\n"
            @"### 💻 System Specifications\n"
            @"- **OS:** macOS %@\n"
            @"- **Processor:** Intel Core i5-8350U (4 Cores / 8 Threads)\n"
            @"- **Base / Boost Frequency:** 1.70 GHz / 3.60 GHz\n\n"
            @"### ⚡ Power & Voltage (Real-Time)\n"
            @"- **Package Power:** %@\n"
            @"- **Core Power:** %@\n"
            @"- **GT Power:** %@\n"
            @"- **Core Voltage:** %@\n\n"
            @"### 🌡️ Thermal Metrics (Tj. Max: 100°C)\n"
            @"- **Package Temp:** %@ (Min: %.1f°C, Max: %.1f°C)\n"
            @"- **Core #0:** %@\n"
            @"- **Core #1:** %@\n"
            @"- **Core #2:** %@\n"
            @"- **Core #3:** %@\n\n"
            @"### 🎮 GPU & Memory\n"
            @"- **GPU Utilization:** %@\n"
            @"- **GPU Details:** %@\n"
            @"- **RAM Usage:** %@\n"
            @"- **Disk:** %@\n",
            userNote, ts,
            [[NSProcessInfo processInfo] operatingSystemVersionString],
            _procPowerLabel.stringValue,
            _procCorePowerLabel.stringValue,
            _procGtPowerLabel.stringValue,
            _procVoltageLabel.stringValue,
            _tempValLabel.stringValue, _minPkgTemp, _maxPkgTemp,
            _coreRows[0].tempCurLabel.stringValue,
            _coreRows[1].tempCurLabel.stringValue,
            _coreRows[2].tempCurLabel.stringValue,
            _coreRows[3].tempCurLabel.stringValue,
            _gpuValLabel.stringValue,
            _gpuSubLabel.stringValue,
            _ramSubLabel.stringValue,
            _diskLabel.stringValue
        ];

        // Execute gh issue create automatically
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:@"/bin/zsh"];
        NSString *cmd = [NSString stringWithFormat:
            @"export PATH=\"$HOME/.local/bin:/usr/local/bin:$PATH\"; "
            @"gh issue create --repo SanketRohilla/SysPulse --title '%@' --body '%@'",
            reportTitle, reportContent];
        [task setArguments:@[@"-c", cmd]];

        NSPipe *pipe = [NSPipe pipe];
        [task setStandardOutput:pipe];
        [task setStandardError:pipe];

        [task launch];
        [task waitUntilExit];

        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        NSString *outStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

        if (task.terminationStatus == 0) {
            NSAlert *success = [[NSAlert alloc] init];
            success.messageText = @"Report Sent Successfully!";
            success.informativeText = [NSString stringWithFormat:@"Issue has been automatically created on your GitHub repository:\n%@", outStr];
            [success addButtonWithTitle:@"Open on GitHub"];
            [success addButtonWithTitle:@"OK"];
            if ([success runModal] == NSAlertFirstButtonReturn) {
                NSString *cleanUrl = [outStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSArray *lines = [cleanUrl componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
                NSString *urlStr = lines.lastObject;
                if ([urlStr hasPrefix:@"http"]) {
                    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlStr]];
                }
            }
        } else {
            NSAlert *err = [[NSAlert alloc] init];
            err.messageText = @"Failed to Send Report";
            err.informativeText = [NSString stringWithFormat:@"Error from GitHub CLI:\n%@", outStr];
            [err runModal];
        }
    } else if (resp == NSAlertSecondButtonReturn) {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        NSString *diag = [NSString stringWithFormat:
            @"=== SysPulse Diagnostic Report ===\n"
            @"OS: macOS %@\n"
            @"CPU: Intel Core i5-8350U (4 Cores / 8 Threads)\n"
            @"Package Temp: %@ (Min: %.1f°C, Max: %.1f°C)\n"
            @"Package Power: %@ | Core Power: %@ | GT Power: %@\n"
            @"Core VID: %@\n"
            @"GPU: %@ (%@)\n"
            @"RAM: %@\n",
            [[NSProcessInfo processInfo] operatingSystemVersionString],
            _tempValLabel.stringValue, _minPkgTemp, _maxPkgTemp,
            _procPowerLabel.stringValue, _procCorePowerLabel.stringValue, _procGtPowerLabel.stringValue,
            _procVoltageLabel.stringValue,
            _gpuValLabel.stringValue, _gpuSubLabel.stringValue,
            _ramSubLabel.stringValue
        ];
        [pb setString:diag forType:NSPasteboardTypeString];

        NSAlert *done = [[NSAlert alloc] init];
        done.messageText = @"Diagnostics Copied to Clipboard";
        done.informativeText = @"System diagnostic information has been copied to your clipboard!";
        [done runModal];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO; // Keep running in menu bar even if window closed
}

@end

// -----------------------------------------------------------------------------
// Application Entry Point
// -----------------------------------------------------------------------------
static SysPulseAppDelegate *g_delegate = nil;

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        g_delegate = [[SysPulseAppDelegate alloc] init];
        [app setDelegate:g_delegate];

        NSMenu *mainMenu = [[NSMenu alloc] init];
        NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
        [mainMenu addItem:appMenuItem];

        NSMenu *appMenu = [[NSMenu alloc] init];
        [appMenu addItemWithTitle:@"About SysPulse" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
        [appMenu addItem:[NSMenuItem separatorItem]];
        [appMenu addItemWithTitle:@"Hide SysPulse" action:@selector(hide:) keyEquivalent:@"h"];
        [appMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
        [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
        [appMenu addItem:[NSMenuItem separatorItem]];
        [appMenu addItemWithTitle:@"Quit SysPulse" action:@selector(terminate:) keyEquivalent:@"q"];
        [appMenuItem setSubmenu:appMenu];

        [app setMainMenu:mainMenu];

        [app activateIgnoringOtherApps:YES];
        [app run];
    }
    return 0;
}

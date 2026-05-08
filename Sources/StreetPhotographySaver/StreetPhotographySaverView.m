#import "StreetPhotographySaverView.h"

@interface StreetPhotographySaverView ()
@property(nonatomic, strong) NSImageView *imageView;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, copy) NSArray<NSURL *> *imageURLs;
@property(nonatomic) NSUInteger currentImageIndex;
@property(nonatomic, strong) NSDate *lastAdvance;
@end

@implementation StreetPhotographySaverView

static NSTimeInterval const StreetPhotographyDisplaySeconds = 8.0;

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview {
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        [self setAnimationTimeInterval:1.0 / 30.0];
        [self setupView];
        [self loadCachedImages];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setAnimationTimeInterval:1.0 / 30.0];
        [self setupView];
        [self loadCachedImages];
    }
    return self;
}

- (BOOL)hasConfigureSheet {
    return NO;
}

- (void)animateOneFrame {
    if (self.imageURLs.count == 0) {
        [self loadCachedImagesIfAvailable];
        return;
    }

    if ([[NSDate date] timeIntervalSinceDate:self.lastAdvance] >= StreetPhotographyDisplaySeconds) {
        [self showNextPhoto];
    }
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    self.imageView.frame = self.bounds;
    self.statusLabel.frame = NSInsetRect(self.bounds, 36, 36);
}

- (void)setupView {
    self.wantsLayer = YES;
    self.layer.backgroundColor = NSColor.blackColor.CGColor;
    self.imageURLs = @[];
    self.lastAdvance = NSDate.distantPast;

    self.imageView = [[NSImageView alloc] initWithFrame:self.bounds];
    self.imageView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.imageView.imageAlignment = NSImageAlignCenter;
    self.imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [self addSubview:self.imageView];

    self.statusLabel = [NSTextField labelWithString:@"Loading Street Photography cache..."];
    self.statusLabel.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.statusLabel.alignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = NSColor.whiteColor;
    self.statusLabel.font = [NSFont systemFontOfSize:24 weight:NSFontWeightMedium];
    self.statusLabel.backgroundColor = NSColor.clearColor;
    self.statusLabel.frame = NSInsetRect(self.bounds, 36, 36);
    [self addSubview:self.statusLabel];
}

- (void)loadCachedImagesIfAvailable {
    NSArray<NSURL *> *urls = [self cachedImageURLs];
    if (urls.count > 0) {
        self.imageURLs = [self shuffledURLs:urls];
        self.currentImageIndex = 0;
        self.statusLabel.hidden = YES;
        [self showNextPhoto];
    }
}

- (void)loadCachedImages {
    [self loadCachedImagesIfAvailable];
    if (self.imageURLs.count == 0) {
        [self showStatus:@"Run Street Photography Sync to cache photos from the Photos album."];
    }
}

- (NSArray<NSURL *> *)cachedImageURLs {
    NSURL *cacheURL = [self cacheDirectoryURL];
    NSArray<NSURL *> *contents = [NSFileManager.defaultManager contentsOfDirectoryAtURL:cacheURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    NSMutableArray<NSURL *> *imageURLs = [NSMutableArray array];
    NSSet<NSString *> *extensions = [NSSet setWithObjects:@"jpg", @"jpeg", @"png", nil];

    for (NSURL *url in contents) {
        if ([extensions containsObject:url.pathExtension.lowercaseString]) {
            [imageURLs addObject:url];
        }
    }

    return [imageURLs copy];
}

- (NSURL *)cacheDirectoryURL {
    return [[NSBundle bundleForClass:self.class].resourceURL URLByAppendingPathComponent:@"Cache" isDirectory:YES];
}

- (void)showNextPhoto {
    if (self.imageURLs.count == 0) {
        return;
    }

    NSURL *imageURL = self.imageURLs[self.currentImageIndex];
    self.currentImageIndex = (self.currentImageIndex + 1) % self.imageURLs.count;
    if (self.currentImageIndex == 0) {
        self.imageURLs = [self shuffledURLs:self.imageURLs];
    }

    NSImage *image = [[NSImage alloc] initWithContentsOfURL:imageURL];
    if (!image) {
        [self loadCachedImagesIfAvailable];
        return;
    }

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 1.2;
        self.imageView.animator.alphaValue = 0.0;
    } completionHandler:^{
        self.imageView.image = image;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 1.2;
            self.imageView.animator.alphaValue = 1.0;
        } completionHandler:nil];
    }];
    self.lastAdvance = [NSDate date];
}

- (NSArray<NSURL *> *)shuffledURLs:(NSArray<NSURL *> *)urls {
    NSMutableArray<NSURL *> *shuffled = [urls mutableCopy];
    for (NSUInteger i = shuffled.count; i > 1; i--) {
        NSUInteger j = SSRandomIntBetween(0, (int)i - 1);
        [shuffled exchangeObjectAtIndex:i - 1 withObjectAtIndex:j];
    }
    return shuffled;
}

- (void)showStatus:(NSString *)message {
    self.imageView.image = nil;
    self.statusLabel.stringValue = message;
    self.statusLabel.hidden = NO;
}

@end

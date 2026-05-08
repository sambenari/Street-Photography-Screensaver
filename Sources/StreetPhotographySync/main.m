#import <AppKit/AppKit.h>
#import <Photos/Photos.h>

static NSString * const AlbumName = @"Street Photography";
static CGFloat const MaxExportDimension = 3840.0;

static NSArray<NSString *> *PreferredAlbumNames(void) {
    return @[AlbumName, @"Street Photorgraphy"];
}

@interface SyncDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSProgressIndicator *progressIndicator;
@property(nonatomic, copy) NSString *matchedAlbumTitle;
@end

@implementation SyncDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildWindow];
    [self sync];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 520, 180);
    self.window = [[NSWindow alloc] initWithContentRect:frame styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable) backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Street Photography Sync";
    self.window.releasedWhenClosed = NO;
    [self.window center];

    NSView *content = self.window.contentView;
    self.statusLabel = [NSTextField labelWithString:@"Preparing Photos sync..."];
    self.statusLabel.frame = NSMakeRect(28, 92, 464, 48);
    self.statusLabel.font = [NSFont systemFontOfSize:16 weight:NSFontWeightMedium];
    self.statusLabel.alignment = NSTextAlignmentCenter;
    self.statusLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.statusLabel.maximumNumberOfLines = 2;
    [content addSubview:self.statusLabel];

    self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(56, 54, 408, 18)];
    self.progressIndicator.indeterminate = YES;
    [self.progressIndicator startAnimation:nil];
    [content addSubview:self.progressIndicator];

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)setStatus:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.stringValue = status;
    });
}

- (void)sync {
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) {
        [self exportAlbum];
        return;
    }

    if (status == PHAuthorizationStatusNotDetermined) {
        [self setStatus:@"Requesting Photos access..."];
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus requestStatus) {
            if (requestStatus == PHAuthorizationStatusAuthorized || requestStatus == PHAuthorizationStatusLimited) {
                [self exportAlbum];
            } else {
                [self finishWithMessage:@"Photos access was not granted." success:NO];
            }
        }];
        return;
    }

    [self finishWithMessage:@"Photos access is denied. Enable it for Street Photography Sync in System Settings." success:NO];
}

- (void)exportAlbum {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<PHAssetCollection *> *albums = @[];
        for (NSString *candidateName in PreferredAlbumNames()) {
            albums = [self findAlbumCollectionsNamed:candidateName];
            if (albums.count > 0) {
                break;
            }
        }

        if (albums.count == 0) {
            NSURL *reportURL = [self writeVisibleAlbumReport];
            NSString *message = reportURL
                ? [NSString stringWithFormat:@"Album \"%@\" was not found. I wrote visible album names to %@.", AlbumName, reportURL.path]
                : [NSString stringWithFormat:@"Album \"%@\" was not found.", AlbumName];
            [self finishWithMessage:message success:NO];
            return;
        }

        PHFetchOptions *assetOptions = [[PHFetchOptions alloc] init];
        assetOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
        assetOptions.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d", PHAssetMediaTypeImage];
        NSMutableArray<PHAsset *> *assetList = [NSMutableArray array];
        NSMutableSet<NSString *> *seenLocalIdentifiers = [NSMutableSet set];
        for (PHAssetCollection *album in albums) {
            PHFetchResult<PHAsset *> *fetchedAssets = [PHAsset fetchAssetsInAssetCollection:album options:assetOptions];
            [fetchedAssets enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
                if (![seenLocalIdentifiers containsObject:asset.localIdentifier]) {
                    [seenLocalIdentifiers addObject:asset.localIdentifier];
                    [assetList addObject:asset];
                }
            }];
        }
        NSArray<PHAsset *> *assets = [assetList copy];
        if (assets.count == 0) {
            [self finishWithMessage:[NSString stringWithFormat:@"\"%@\" has no photos in its visible album(s).", self.matchedAlbumTitle ?: AlbumName] success:NO];
            return;
        }

        NSError *error = nil;
        NSURL *cacheURL = [self cacheDirectoryURL];
        NSURL *stagingURL = [[cacheURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"CacheStaging" isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:stagingURL withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            [self finishWithMessage:[NSString stringWithFormat:@"Could not create cache: %@", error.localizedDescription] success:NO];
            return;
        }

        __block NSUInteger exportedCount = 0;
        [assets enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
            @autoreleasepool {
                [self setStatus:[NSString stringWithFormat:@"Exporting %lu of %lu...", (unsigned long)idx + 1, (unsigned long)assets.count]];
                NSImage *image = [self imageForAsset:asset];
                if (!image) {
                    return;
                }

                NSURL *outputURL = [stagingURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%05lu-%@.jpg", (unsigned long)idx, asset.localIdentifier.lastPathComponent]];
                if ([self writeJPEGImage:image toURL:outputURL]) {
                    exportedCount++;
                }
            }
        }];

        if (exportedCount == 0) {
            [self finishWithMessage:@"No images could be exported from the album." success:NO];
            return;
        }

        NSURL *oldCacheURL = [[cacheURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"CacheOld" isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:cacheURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [NSFileManager.defaultManager moveItemAtURL:cacheURL toURL:oldCacheURL error:nil];
        if (![NSFileManager.defaultManager moveItemAtURL:stagingURL toURL:cacheURL error:&error]) {
            [self finishWithMessage:[NSString stringWithFormat:@"Could not install cache: %@", error.localizedDescription] success:NO];
            return;
        }
        [NSFileManager.defaultManager removeItemAtURL:oldCacheURL error:nil];

        [self setStatus:@"Embedding cache into the screen saver..."];
        NSError *embedError = nil;
        if (![self installEmbeddedCacheFromURL:cacheURL error:&embedError]) {
            [self finishWithMessage:[NSString stringWithFormat:@"Synced %lu photo(s), but could not update the screen saver bundle: %@", (unsigned long)exportedCount, embedError.localizedDescription] success:NO];
            return;
        }

        [self finishWithMessage:[NSString stringWithFormat:@"Synced and embedded %lu photo(s) from \"%@\". You can close this app.", (unsigned long)exportedCount, self.matchedAlbumTitle ?: AlbumName] success:YES];
    });
}

- (NSArray<PHAssetCollection *> *)findAlbumCollectionsNamed:(NSString *)name {
    NSString *target = [self normalizedAlbumName:name];
    NSMutableArray<PHAssetCollection *> *collections = [NSMutableArray array];

    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.predicate = [NSPredicate predicateWithFormat:@"localizedTitle ==[cd] %@", name];

    PHFetchResult<PHAssetCollection *> *userAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:options];
    if (userAlbums.firstObject) {
        self.matchedAlbumTitle = userAlbums.firstObject.localizedTitle;
        return @[userAlbums.firstObject];
    }

    PHFetchResult<PHAssetCollection *> *smartAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeAny options:options];
    if (smartAlbums.firstObject) {
        self.matchedAlbumTitle = smartAlbums.firstObject.localizedTitle;
        return @[smartAlbums.firstObject];
    }

    NSArray<PHAssetCollection *> *exactFolderAlbums = [self albumCollectionsInsideCollectionListNamed:name normalizedTarget:target exactOnly:YES];
    if (exactFolderAlbums.count > 0) {
        return exactFolderAlbums;
    }

    [collections addObjectsFromArray:[self allAlbumCollectionsWithType:PHAssetCollectionTypeAlbum]];
    [collections addObjectsFromArray:[self allAlbumCollectionsWithType:PHAssetCollectionTypeSmartAlbum]];

    for (PHAssetCollection *collection in collections) {
        NSString *title = collection.localizedTitle ?: @"";
        if ([[self normalizedAlbumName:title] isEqualToString:target]) {
            self.matchedAlbumTitle = title;
            return @[collection];
        }
    }

    NSArray<NSString *> *tokens = [target componentsSeparatedByString:@" "];
    for (PHAssetCollection *collection in collections) {
        NSString *title = collection.localizedTitle ?: @"";
        NSString *normalizedTitle = [self normalizedAlbumName:title];
        BOOL containsAllTokens = YES;
        for (NSString *token in tokens) {
            if (token.length > 0 && [normalizedTitle rangeOfString:token].location == NSNotFound) {
                containsAllTokens = NO;
                break;
            }
        }

        if (containsAllTokens) {
            self.matchedAlbumTitle = title;
            return @[collection];
        }
    }

    PHAssetCollection *closestAlbum = [self closestAssetCollectionInCollections:collections normalizedTarget:target];
    if (closestAlbum) {
        self.matchedAlbumTitle = closestAlbum.localizedTitle;
        return @[closestAlbum];
    }

    NSArray<PHAssetCollection *> *fuzzyFolderAlbums = [self albumCollectionsInsideCollectionListNamed:name normalizedTarget:target exactOnly:NO];
    if (fuzzyFolderAlbums.count > 0) {
        return fuzzyFolderAlbums;
    }

    return @[];
}

- (PHAssetCollection *)closestAssetCollectionInCollections:(NSArray<PHAssetCollection *> *)collections normalizedTarget:(NSString *)target {
    PHAssetCollection *closest = nil;
    NSUInteger closestDistance = NSUIntegerMax;

    for (PHAssetCollection *collection in collections) {
        NSString *title = collection.localizedTitle ?: @"";
        NSString *normalizedTitle = [self normalizedAlbumName:title];
        if ([normalizedTitle hasPrefix:@"street "]) {
            NSUInteger distance = [self editDistanceFromString:target toString:normalizedTitle maximumDistance:4];
            if (distance < closestDistance) {
                closestDistance = distance;
                closest = collection;
            }
        }
    }

    return closestDistance <= 4 ? closest : nil;
}

- (NSArray<PHAssetCollection *> *)allAlbumCollectionsWithType:(PHAssetCollectionType)type {
    PHFetchResult<PHAssetCollection *> *result = [PHAssetCollection fetchAssetCollectionsWithType:type subtype:PHAssetCollectionSubtypeAny options:nil];
    NSMutableArray<PHAssetCollection *> *collections = [NSMutableArray arrayWithCapacity:result.count];
    [result enumerateObjectsUsingBlock:^(PHAssetCollection *collection, NSUInteger idx, BOOL *stop) {
        if (collection.localizedTitle.length > 0) {
            [collections addObject:collection];
        }
    }];
    return collections;
}

- (NSArray<PHAssetCollection *> *)albumCollectionsInsideCollectionListNamed:(NSString *)name normalizedTarget:(NSString *)target exactOnly:(BOOL)exactOnly {
    NSMutableArray<PHCollectionList *> *lists = [NSMutableArray array];
    [lists addObjectsFromArray:[self allCollectionListsWithType:PHCollectionListTypeFolder]];
    [lists addObjectsFromArray:[self allCollectionListsWithType:PHCollectionListTypeSmartFolder]];

    NSArray<NSString *> *tokens = [target componentsSeparatedByString:@" "];
    for (PHCollectionList *list in lists) {
        NSString *title = list.localizedTitle ?: @"";
        NSString *normalizedTitle = [self normalizedAlbumName:title];
        BOOL matches = [normalizedTitle isEqualToString:target] || [title localizedCaseInsensitiveCompare:name] == NSOrderedSame;

        if (!matches && !exactOnly) {
            matches = YES;
            for (NSString *token in tokens) {
                if (token.length > 0 && [normalizedTitle rangeOfString:token].location == NSNotFound) {
                    matches = NO;
                    break;
                }
            }
        }

        if (matches) {
            NSMutableArray<PHAssetCollection *> *albums = [NSMutableArray array];
            [self appendAssetCollectionsInsideCollectionList:list toArray:albums];
            if (albums.count > 0) {
                self.matchedAlbumTitle = title;
                return albums;
            }
        }
    }
    return @[];
}

- (NSArray<PHCollectionList *> *)allCollectionListsWithType:(PHCollectionListType)type {
    PHFetchResult<PHCollectionList *> *result = [PHCollectionList fetchCollectionListsWithType:type subtype:PHCollectionListSubtypeAny options:nil];
    NSMutableArray<PHCollectionList *> *lists = [NSMutableArray arrayWithCapacity:result.count];
    [result enumerateObjectsUsingBlock:^(PHCollectionList *list, NSUInteger idx, BOOL *stop) {
        if (list.localizedTitle.length > 0) {
            [lists addObject:list];
        }
    }];
    return lists;
}

- (void)appendAssetCollectionsInsideCollectionList:(PHCollectionList *)list toArray:(NSMutableArray<PHAssetCollection *> *)albums {
    PHFetchResult<PHCollection *> *children = [PHCollectionList fetchCollectionsInCollectionList:list options:nil];
    [children enumerateObjectsUsingBlock:^(PHCollection *collection, NSUInteger idx, BOOL *stop) {
        if ([collection isKindOfClass:PHAssetCollection.class]) {
            [albums addObject:(PHAssetCollection *)collection];
        } else if ([collection isKindOfClass:PHCollectionList.class]) {
            [self appendAssetCollectionsInsideCollectionList:(PHCollectionList *)collection toArray:albums];
        }
    }];
}

- (NSString *)normalizedAlbumName:(NSString *)name {
    NSString *folded = [[name stringByFoldingWithOptions:(NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch) locale:NSLocale.currentLocale] lowercaseString];
    NSCharacterSet *allowed = [NSCharacterSet alphanumericCharacterSet];
    NSMutableString *normalized = [NSMutableString string];
    BOOL previousWasSpace = YES;

    for (NSUInteger i = 0; i < folded.length; i++) {
        unichar character = [folded characterAtIndex:i];
        if ([allowed characterIsMember:character]) {
            [normalized appendFormat:@"%C", character];
            previousWasSpace = NO;
        } else if (!previousWasSpace) {
            [normalized appendString:@" "];
            previousWasSpace = YES;
        }
    }

    return [normalized stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

- (NSUInteger)editDistanceFromString:(NSString *)left toString:(NSString *)right maximumDistance:(NSUInteger)maximumDistance {
    NSUInteger leftLength = left.length;
    NSUInteger rightLength = right.length;
    if (labs((long)leftLength - (long)rightLength) > (long)maximumDistance) {
        return maximumDistance + 1;
    }

    NSMutableArray<NSNumber *> *previous = [NSMutableArray arrayWithCapacity:rightLength + 1];
    NSMutableArray<NSNumber *> *current = [NSMutableArray arrayWithCapacity:rightLength + 1];
    for (NSUInteger j = 0; j <= rightLength; j++) {
        [previous addObject:@(j)];
        [current addObject:@0];
    }

    for (NSUInteger i = 1; i <= leftLength; i++) {
        current[0] = @(i);
        NSUInteger rowMinimum = i;
        unichar leftCharacter = [left characterAtIndex:i - 1];

        for (NSUInteger j = 1; j <= rightLength; j++) {
            unichar rightCharacter = [right characterAtIndex:j - 1];
            NSUInteger substitutionCost = leftCharacter == rightCharacter ? 0 : 1;
            NSUInteger deletion = previous[j].unsignedIntegerValue + 1;
            NSUInteger insertion = current[j - 1].unsignedIntegerValue + 1;
            NSUInteger substitution = previous[j - 1].unsignedIntegerValue + substitutionCost;
            NSUInteger value = MIN(MIN(deletion, insertion), substitution);
            current[j] = @(value);
            rowMinimum = MIN(rowMinimum, value);
        }

        if (rowMinimum > maximumDistance) {
            return maximumDistance + 1;
        }

        NSMutableArray<NSNumber *> *swap = previous;
        previous = current;
        current = swap;
    }

    return previous[rightLength].unsignedIntegerValue;
}

- (NSURL *)writeVisibleAlbumReport {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (PHAssetCollection *collection in [self allAlbumCollectionsWithType:PHAssetCollectionTypeAlbum]) {
        [titles addObject:collection.localizedTitle];
    }
    for (PHAssetCollection *collection in [self allAlbumCollectionsWithType:PHAssetCollectionTypeSmartAlbum]) {
        [titles addObject:collection.localizedTitle];
    }

    NSMutableArray<NSString *> *folders = [NSMutableArray array];
    for (PHCollectionList *list in [self allCollectionListsWithType:PHCollectionListTypeFolder]) {
        [folders addObject:list.localizedTitle];
    }
    for (PHCollectionList *list in [self allCollectionListsWithType:PHCollectionListTypeSmartFolder]) {
        [folders addObject:list.localizedTitle];
    }

    [titles sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [folders sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSString *body = [NSString stringWithFormat:@"Visible Photos albums:\n\n%@\n\nVisible Photos folders:\n\n%@\n", [titles componentsJoinedByString:@"\n"], [folders componentsJoinedByString:@"\n"]];
    NSURL *desktopURL = [NSFileManager.defaultManager URLsForDirectory:NSDesktopDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *reportURL = [desktopURL URLByAppendingPathComponent:@"Street Photography Albums.txt"];

    NSError *error = nil;
    if (![body writeToURL:reportURL atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        return nil;
    }
    return reportURL;
}

- (NSImage *)imageForAsset:(PHAsset *)asset {
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    options.resizeMode = PHImageRequestOptionsResizeModeExact;
    options.networkAccessAllowed = YES;
    options.synchronous = YES;

    CGFloat longestSide = MAX(asset.pixelWidth, asset.pixelHeight);
    CGFloat scale = longestSide > MaxExportDimension ? MaxExportDimension / longestSide : 1.0;
    CGSize targetSize = CGSizeMake(MAX(1, asset.pixelWidth * scale), MAX(1, asset.pixelHeight * scale));

    __block NSImage *result = nil;
    [[PHImageManager defaultManager] requestImageForAsset:asset targetSize:targetSize contentMode:PHImageContentModeAspectFit options:options resultHandler:^(NSImage *image, NSDictionary *info) {
        result = image;
    }];
    return result;
}

- (BOOL)writeJPEGImage:(NSImage *)image toURL:(NSURL *)url {
    NSData *tiffData = image.TIFFRepresentation;
    if (!tiffData) {
        return NO;
    }

    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:tiffData];
    NSData *jpegData = [bitmap representationUsingType:NSBitmapImageFileTypeJPEG properties:@{NSImageCompressionFactor: @0.92}];
    return [jpegData writeToURL:url atomically:YES];
}

- (NSURL *)cacheDirectoryURL {
    NSString *cachePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Screen Savers/Street Photography Cache"];
    return [NSURL fileURLWithPath:cachePath isDirectory:YES];
}

- (NSURL *)installedSaverURL {
    NSString *saverPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Screen Savers/Street Photography.saver"];
    return [NSURL fileURLWithPath:saverPath isDirectory:YES];
}

- (BOOL)installEmbeddedCacheFromURL:(NSURL *)cacheURL error:(NSError **)error {
    NSURL *saverURL = [self installedSaverURL];
    NSURL *resourcesURL = [saverURL URLByAppendingPathComponent:@"Contents/Resources" isDirectory:YES];
    NSURL *embeddedCacheURL = [resourcesURL URLByAppendingPathComponent:@"Cache" isDirectory:YES];
    NSURL *stagingURL = [resourcesURL URLByAppendingPathComponent:[NSString stringWithFormat:@"CacheStaging-%@", NSUUID.UUID.UUIDString] isDirectory:YES];
    NSURL *oldCacheURL = [resourcesURL URLByAppendingPathComponent:[NSString stringWithFormat:@"CacheOld-%@", NSUUID.UUID.UUIDString] isDirectory:YES];

    if (![NSFileManager.defaultManager fileExistsAtPath:saverURL.path]) {
        if (error) {
            *error = [NSError errorWithDomain:@"StreetPhotographySync" code:10 userInfo:@{NSLocalizedDescriptionKey: @"Street Photography.saver is not installed in ~/Library/Screen Savers."}];
        }
        return NO;
    }

    if (![NSFileManager.defaultManager createDirectoryAtURL:resourcesURL withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    [NSFileManager.defaultManager removeItemAtURL:stagingURL error:nil];
    if (![NSFileManager.defaultManager copyItemAtURL:cacheURL toURL:stagingURL error:error]) {
        return NO;
    }

    [NSFileManager.defaultManager moveItemAtURL:embeddedCacheURL toURL:oldCacheURL error:nil];
    if (![NSFileManager.defaultManager moveItemAtURL:stagingURL toURL:embeddedCacheURL error:error]) {
        [NSFileManager.defaultManager moveItemAtURL:oldCacheURL toURL:embeddedCacheURL error:nil];
        return NO;
    }
    [NSFileManager.defaultManager removeItemAtURL:oldCacheURL error:nil];

    if (![self runToolAtPath:@"/usr/bin/xattr" arguments:@[@"-cr", saverURL.path] error:error]) {
        return NO;
    }
    if (![self runToolAtPath:@"/usr/bin/codesign" arguments:@[@"--force", @"--sign", @"-", saverURL.path] error:error]) {
        return NO;
    }

    [self runToolAtPath:@"/usr/bin/killall" arguments:@[@"legacyScreenSaver"] error:nil];
    [self runToolAtPath:@"/usr/bin/killall" arguments:@[@"ScreenSaverEngine"] error:nil];
    return YES;
}

- (BOOL)runToolAtPath:(NSString *)path arguments:(NSArray<NSString *> *)arguments error:(NSError **)error {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = arguments;

    NSPipe *errorPipe = [NSPipe pipe];
    task.standardError = errorPipe;
    task.standardOutput = [NSPipe pipe];

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (error) {
            *error = launchError;
        }
        return NO;
    }

    [task waitUntilExit];
    if (task.terminationStatus == 0) {
        return YES;
    }

    NSData *errorData = [errorPipe.fileHandleForReading readDataToEndOfFile];
    NSString *errorOutput = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding] ?: @"";
    NSString *description = errorOutput.length > 0
        ? errorOutput
        : [NSString stringWithFormat:@"%@ exited with status %d.", path.lastPathComponent, task.terminationStatus];

    if (error) {
        *error = [NSError errorWithDomain:@"StreetPhotographySync" code:task.terminationStatus userInfo:@{NSLocalizedDescriptionKey: description}];
    }
    return NO;
}

- (void)finishWithMessage:(NSString *)message success:(BOOL)success {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.stringValue = message;
        self.progressIndicator.hidden = YES;
        [self.progressIndicator stopAnimation:nil];
        if (success) {
            NSBeep();
        }
    });
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        SyncDelegate *delegate = [[SyncDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}

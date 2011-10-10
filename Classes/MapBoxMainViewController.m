//
//  MapBoxMainViewController.m
//  MapBoxiPad
//
//  Created by Justin R. Miller on 6/17/10.
//  Copyright Development Seed 2010. All rights reserved.
//

#import "MapBoxMainViewController.h"

#import "MapBoxAppDelegate.h"

#import "DSMapView.h"
#import "DSMapBoxTileSetManager.h"
#import "DSMapBoxDataOverlayManager.h"
#import "DSMapContents.h"
#import "DSMapBoxDocumentSaveController.h"
#import "DSMapBoxMarkerManager.h"
#import "DSMapBoxHelpController.h"
#import "DSMapBoxFeedParser.h"
#import "DSMapBoxLayerAddTileStreamAlbumController.h"
#import "DSMapBoxLayerAddTileStreamBrowseController.h"
#import "DSMapBoxAlphaModalNavigationController.h"
#import "DSMapBoxTintedBarButtonItem.h"
#import "DSMapBoxTileSourceInfiniteZoom.h"
#import "DSMapBoxGeoJSONParser.h"
#import "DSMapBoxAlertView.h"

#import "UIViewController_Additions.h"
#import "UIApplication_Additions.h"
#import "DSSound.h"

#import "SimpleKML.h"

#import "RMTileSource.h"
#import "RMOpenStreetMapSource.h"
#import "RMMapQuestOSMSource.h"
#import "RMMBTilesTileSource.h"
#import "RMTileStreamSource.h"

#import "TouchXML.h"

#import <QuartzCore/QuartzCore.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <MobileCoreServices/UTType.h>

#import "Reachability.h"

#import "UIImage+Alpha.h"

@interface MapBoxMainViewController (MapBoxMainViewControllerPrivate)

- (void)offlineAlert;
- (UIImage *)mapSnapshot;
- (void)layerImportAlertWithName:(NSString *)name;
- (void)setClusteringOn:(BOOL)clusteringOn;

@end

#pragma mark -

@implementation MapBoxMainViewController

@synthesize badParseURL;
@synthesize lastLayerAlertDate;

- (void)viewDidLoad
{
    [super viewDidLoad];

    // starting setup info
    //
    CLLocationCoordinate2D startingPoint;
    
    startingPoint.latitude  = kStartingLat;
    startingPoint.longitude = kStartingLon;
    
    // base view & map view
    //
    self.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"loading.png"]];
    
    RMMBTilesTileSource *source = [[[RMMBTilesTileSource alloc] initWithTileSetURL:[[DSMapBoxTileSetManager defaultManager] defaultTileSetURL]] autorelease];
    
	[[[DSMapContents alloc] initWithView:mapView 
                              tilesource:source
                            centerLatLon:startingPoint
                               zoomLevel:kStartingZoom
                            maxZoomLevel:[source maxZoom]
                            minZoomLevel:[source minZoom]
                         backgroundImage:nil] autorelease];
    
    mapView.enableRotate = NO;
    mapView.deceleration = NO;
    
    mapView.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"loading.png"]];

    mapView.contents.zoom = kStartingZoom;

    // hide cluster button to start
    //
    [toolbar setItems:[[NSMutableArray arrayWithArray:toolbar.items] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"NOT SELF = %@", clusteringButton]] animated:NO];
    
    // setup toolbar items as exclusive actions
    //
    for (id item in toolbar.items)
        if ([item isKindOfClass:[UIBarButtonItem class]])
            [self manageExclusiveItem:item];
    
    // data overlay & layer managers
    //
    dataOverlayManager = [[DSMapBoxDataOverlayManager alloc] initWithMapView:mapView];
    dataOverlayManager.mapView = mapView;
    mapView.delegate = dataOverlayManager;
    mapView.interactivityDelegate = dataOverlayManager;
    layerManager = [[DSMapBoxLayerManager alloc] initWithDataOverlayManager:dataOverlayManager overBaseMapView:mapView];
    layerManager.delegate = self;
    
    // watch for net changes
    //
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityDidChange:)
                                                 name:kReachabilityChangedNotification
                                               object:nil];
    
    reachability = [[Reachability reachabilityForInternetConnection] retain];
    [reachability startNotifier];
    
    // watch for zoom bounds limits
    //
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(zoomBoundsReached:)
                                                 name:DSMapContentsZoomBoundsReached
                                               object:nil];
    
    self.lastLayerAlertDate = [NSDate date];
    
    // watch for new layer additions
    //
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(layersAdded:)
                                                 name:DSMapBoxLayersAdded
                                               object:nil];
    
    // restore app state
    //
    [self restoreState:self];
    
    // warn about any zipped mbtiles
    //
    BOOL showedZipAlert = NO;
    
    NSPredicate *zippedPredicate = [NSPredicate predicateWithFormat:@"self ENDSWITH '.mbtiles.zip'"];
    
    NSArray *zippedTiles = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[UIApplication sharedApplication] documentsFolderPath]
                                                                                error:NULL] filteredArrayUsingPredicate:zippedPredicate];
    
    NSMutableSet *seenZips = [NSMutableSet set];
    
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"seenZippedTiles"])
        [seenZips addObjectsFromArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"seenZippedTiles"]];
    
    for (NSString *zippedTile in zippedTiles)
    {
        if ( ! [seenZips containsObject:zippedTile] && ! showedZipAlert)
        {
            NSString *appName = [[NSProcessInfo processInfo] processName];
            
            [seenZips addObject:zippedTile];
            
            UIAlertView *zipAlert = [[[UIAlertView alloc] initWithTitle:@"Zipped Tiles Found"

                                                                message:[NSString stringWithFormat:@"Your %@ documents contain zipped tiles. Please unzip these tiles first in order to use them in %@.", appName, appName] 
                                                               delegate:nil
                                                      cancelButtonTitle:nil
                                                      otherButtonTitles:@"OK", nil] autorelease];
            
            [zipAlert show];
            
            showedZipAlert = YES;
        }
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:[seenZips allObjects] forKey:@"seenZippedTiles"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // make sure online tiles folder exists
    //
    NSString *onlineLayersFolder = [NSString stringWithFormat:@"%@/%@", [[UIApplication sharedApplication] preferencesFolderPath], kTileStreamFolderName];

    [[NSFileManager defaultManager] createDirectoryAtPath:onlineLayersFolder
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    
    // set clustering button state
    //
    if (((DSMapBoxMarkerManager *)mapView.topMostMapView.contents.markerManager).clusteringEnabled)
        [self setClusteringOn:YES];

    else
        [self setClusteringOn:NO];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    postRotationMapCenter = mapView.contents.mapCenter;
    
    return YES;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    mapView.contents.mapCenter = postRotationMapCenter;
    
    if ([mapView.contents isKindOfClass:[DSMapContents class]])
        [mapView.contents performSelector:@selector(postZoom) 
                               withObject:nil 
                               afterDelay:0.0];
    
    [mapView.delegate mapViewRegionDidChange:mapView]; // trigger popover move
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kReachabilityChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DSMapContentsZoomBoundsReached   object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DSMapBoxLayersAdded              object:nil];
    
    [reachability stopNotifier];
    [reachability release];
    
    [layersPopover release];
    [layerManager release];
    [dataOverlayManager release];
    [badParseURL release];
    [documentsActionSheet release];
    [shareActionSheet release];
    [lastLayerAlertDate release];

    [super dealloc];
}

#pragma mark -

- (void)restoreState:(id)sender
{
    NSDictionary *baseMapState;
    NSArray *tileOverlayState;
    NSArray *dataOverlayState;
    
    // determine if document or global restore
    //
    if ([sender isKindOfClass:[NSString class]])
    {
        NSString *saveFile = [NSString stringWithFormat:@"%@/%@/%@.plist", [[UIApplication sharedApplication] preferencesFolderPath], kDSSaveFolderName, sender];
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:saveFile];
        
        baseMapState      = [dict objectForKey:@"baseMapState"];
        tileOverlayState  = [dict objectForKey:@"tileOverlayState"];
        dataOverlayState  = [dict objectForKey:@"dataOverlayState"];
    }
    else
    {
        baseMapState      = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"baseMapState"];
        tileOverlayState  = [[NSUserDefaults standardUserDefaults] arrayForKey:@"tileOverlayState"];
        dataOverlayState  = [[NSUserDefaults standardUserDefaults] arrayForKey:@"dataOverlayState"];
    }

    // load it up
    //
    if (baseMapState)
    {
        // get map center & zoom level
        //
        CLLocationCoordinate2D mapCenter = {
            .latitude  = [[baseMapState objectForKey:@"centerLatitude"]  floatValue],
            .longitude = [[baseMapState objectForKey:@"centerLongitude"] floatValue],
        };
        
        if (mapCenter.latitude <= kUpperLatitudeBounds && mapCenter.latitude >= kLowerLatitudeBounds)
            mapView.contents.mapCenter = mapCenter;
        
        if ([[baseMapState objectForKey:@"zoomLevel"] floatValue] >= kLowerZoomBounds && [[baseMapState objectForKey:@"zoomLevel"] floatValue] <= kUpperZoomBounds)
            mapView.contents.zoom = [[baseMapState objectForKey:@"zoomLevel"] floatValue];
    }
    
    // load tile overlay state(s)
    //
    if (tileOverlayState)
    {
        // remove current layers
        //
        NSArray *activeTileLayers = [layerManager.tileLayers filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"selected = YES"]];
        for (NSDictionary *tileLayer in activeTileLayers)
            [layerManager toggleLayerAtIndexPath:[NSIndexPath indexPathForRow:[layerManager.tileLayers indexOfObject:tileLayer]
                                                                    inSection:DSMapBoxLayerSectionTile]];
        
        // toggle new ones
        //
        BOOL warnedOffline = NO;
        
        for (NSString *tileOverlayURLString in tileOverlayState)
        {
            if ( ! [[NSURL fileURLWithPath:tileOverlayURLString] isEqual:kDSOpenStreetMapURL] &&
                 ! [[NSURL fileURLWithPath:tileOverlayURLString] isEqual:kDSMapQuestOSMURL])
                 tileOverlayURLString = [[[[UIApplication sharedApplication] applicationSandboxFolderPath] stringByAppendingString:@"/"] stringByAppendingString:tileOverlayURLString];
            
            NSURL *tileOverlayURL = [NSURL fileURLWithPath:tileOverlayURLString];
            
            for (NSDictionary *tileLayer in layerManager.tileLayers)
                if ([[tileLayer objectForKey:@"URL"] isEqual:tileOverlayURL] &&
                    ([[NSFileManager defaultManager] fileExistsAtPath:[tileOverlayURL relativePath]] ||
                     [tileOverlayURL isEqual:kDSOpenStreetMapURL] || [tileOverlayURL isEqual:kDSMapQuestOSMURL]))
                    [layerManager toggleLayerAtIndexPath:[NSIndexPath indexPathForRow:[layerManager.tileLayers indexOfObject:tileLayer] 
                                                                            inSection:DSMapBoxLayerSectionTile]];
        
            // notify if any require net & we're offline if loading doc
            //
            if ([sender isKindOfClass:[NSString class]] &&
                ([[NSURL fileURLWithPath:tileOverlayURLString] isEqual:kDSOpenStreetMapURL] || 
                 [[NSURL fileURLWithPath:tileOverlayURLString] isEqual:kDSMapQuestOSMURL]   || 
                 [[NSURL fileURLWithPath:tileOverlayURLString] isTileStreamURL]) &&
                ! warnedOffline && 
                [reachability currentReachabilityStatus] == NotReachable)
            {
                UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"No Internet Connection"
                                                                 message:@"At least one layer requires an internet connection, so it may not appear reliably."
                                                                delegate:nil
                                                       cancelButtonTitle:nil
                                                       otherButtonTitles:@"OK", nil] autorelease];
                
                [alert performSelector:@selector(show) withObject:nil afterDelay:0.0];
                
                warnedOffline = YES;
            }
        }
    }
    
    // load data overlay state(s)
    //
    if (dataOverlayState)
    {
        // remove current layers
        //
        NSArray *activeDataLayers = [layerManager.dataLayers filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"selected = YES"]];
        for (NSDictionary *dataLayer in activeDataLayers)
            [layerManager toggleLayerAtIndexPath:[NSIndexPath indexPathForRow:[layerManager.dataLayers indexOfObject:dataLayer]
                                                                    inSection:DSMapBoxLayerSectionData]];

        // toggle new ones
        //
        for (NSString *dataOverlayURLString in dataOverlayState)
        {
            dataOverlayURLString = [[[[UIApplication sharedApplication] applicationSandboxFolderPath] stringByAppendingString:@"/"] stringByAppendingString:dataOverlayURLString];

            NSURL *dataOverlayURL = [NSURL fileURLWithPath:dataOverlayURLString];
            
            for (NSDictionary *dataLayer in layerManager.dataLayers)
                if ([[dataLayer objectForKey:@"URL"] isEqual:dataOverlayURL] &&
                    [[NSFileManager defaultManager] fileExistsAtPath:[dataOverlayURL relativePath]])
                    [layerManager toggleLayerAtIndexPath:[NSIndexPath indexPathForRow:[layerManager.dataLayers indexOfObject:dataLayer] 
                                                                            inSection:DSMapBoxLayerSectionData]];
        }
    }

    // dismiss document loader
    //
    if ([sender isKindOfClass:[NSString class]])
        [self dismissModalViewControllerAnimated:YES];
}

- (void)saveState:(id)sender
{
    // get snapshot
    //
    NSData *mapSnapshot = UIImageJPEGRepresentation([self mapSnapshot], 1.0);
    
    // get base map state
    //
    NSDictionary *baseMapState = [NSDictionary dictionaryWithObjectsAndKeys:
                                     [NSNumber numberWithFloat:mapView.contents.mapCenter.latitude],            @"centerLatitude",
                                     [NSNumber numberWithFloat:mapView.contents.mapCenter.longitude],           @"centerLongitude",
                                     [NSNumber numberWithFloat:mapView.contents.zoom],                          @"zoomLevel",
                                     nil];
    
    // get tile overlay state(s)
    //
    NSArray *tileOverlayState = [((DSMapContents *)mapView.contents).layerMapViews valueForKeyPath:@"tileSetURL.pathRelativeToApplicationSandbox"];
    
    // get data overlay state(s)
    //
    NSArray *dataOverlayState = [[layerManager.dataLayers filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"selected = YES"]] valueForKeyPath:@"URL.pathRelativeToApplicationSandbox"];

    // determine if document or global save
    //
    if ([sender isKindOfClass:[UIButton class]] || [sender isKindOfClass:[NSString class]])
    {
        NSString *saveFolderPath = [DSMapBoxDocumentLoadController saveFolderPath];
        
        BOOL isDirectory = NO;
        
        if ( ! [[NSFileManager defaultManager] fileExistsAtPath:saveFolderPath isDirectory:&isDirectory] || ! isDirectory)
            [[NSFileManager defaultManager] createDirectoryAtPath:saveFolderPath 
                                      withIntermediateDirectories:YES 
                                                       attributes:nil
                                                            error:NULL];
        
        NSString *stateName = nil;
        
        if ([sender isKindOfClass:[UIButton class]]) // button save
            stateName = saveController.name;
        
        else if ([sender isKindOfClass:[NSString class]]) // load controller save
            stateName = sender;
        
        if ([stateName length] && [[stateName componentsSeparatedByString:@"/"] count] < 2) // no slashes
        {
            if ( ! tileOverlayState)
                tileOverlayState = [NSArray array];
            
            if ( ! dataOverlayState)
                dataOverlayState = [NSArray array];
            
            NSDictionary *state = [NSDictionary dictionaryWithObjectsAndKeys:mapSnapshot,      @"mapSnapshot", 
                                                                             baseMapState,     @"baseMapState", 
                                                                             tileOverlayState, @"tileOverlayState", 
                                                                             dataOverlayState, @"dataOverlayState", 
                                                                             nil];
            
            NSString *savePath = [NSString stringWithFormat:@"%@/%@.plist", saveFolderPath, stateName];
            
            [state writeToFile:savePath atomically:YES];
            
            if (self.modalViewController.modalPresentationStyle == UIModalPresentationFormSheet) // save panel
                [self dismissModalViewControllerAnimated:YES];
        }
    }
    else
    {
        [[NSUserDefaults standardUserDefaults] setObject:mapSnapshot      forKey:@"mapSnapshot"];
        [[NSUserDefaults standardUserDefaults] setObject:baseMapState     forKey:@"baseMapState"];
        [[NSUserDefaults standardUserDefaults] setObject:tileOverlayState forKey:@"tileOverlayState"];
        [[NSUserDefaults standardUserDefaults] setObject:dataOverlayState forKey:@"dataOverlayState"];

        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (IBAction)tappedDocumentsButton:(id)sender
{
    if ( ! documentsActionSheet || ! documentsActionSheet.visible)
    {
        documentsActionSheet = [[UIActionSheet alloc] initWithTitle:nil
                                                           delegate:self
                                                  cancelButtonTitle:nil
                                             destructiveButtonTitle:nil
                                                  otherButtonTitles:@"Load Map", @"Save Map", nil];
        
        [documentsActionSheet showFromBarButtonItem:sender animated:YES];
        
        [self manageExclusiveItem:documentsActionSheet];
    }

    else
        [documentsActionSheet dismissWithClickedButtonIndex:-1 animated:YES];
}

- (void)dismissModal
{
    [self dismissModalViewControllerAnimated:YES];
}

- (void)openKMLFile:(NSURL *)fileURL
{
    NSError *error = nil;
    
    SimpleKML *newKML = [SimpleKML KMLWithContentsOfURL:fileURL error:&error];

    if (error)
        [self dataLayerHandler:self didFailToHandleDataLayerAtURL:fileURL];

    else if (newKML)
    {
        NSString *source      = [fileURL relativePath];
        NSString *filename    = [[fileURL relativePath] lastPathComponent];
        NSString *destination = [NSString stringWithFormat:@"%@/%@", [[UIApplication sharedApplication] documentsFolderPath], filename];
        
        [[NSFileManager defaultManager] copyItemAtPath:source toPath:destination error:NULL];
        
        [self layerImportAlertWithName:[fileURL lastPathComponent]];
        
        [TESTFLIGHT passCheckpoint:@"imported KML"];
    }
}

- (void)openRSSFile:(NSURL *)fileURL
{
    NSArray *feedItems = [DSMapBoxFeedParser itemsForFeed:[NSString stringWithContentsOfURL:fileURL
                                                                                   encoding:NSUTF8StringEncoding
                                                                                      error:NULL]];
    
    if ([feedItems count])
    {
        NSString *source      = [fileURL relativePath];
        NSString *filename    = [[fileURL relativePath] lastPathComponent];
        NSString *destination = [NSString stringWithFormat:@"%@/%@", [[UIApplication sharedApplication] documentsFolderPath], filename];
        
        [[NSFileManager defaultManager] copyItemAtPath:source toPath:destination error:NULL];
        
        [self layerImportAlertWithName:[fileURL lastPathComponent]];
        
        [TESTFLIGHT passCheckpoint:@"imported GeoRSS"];
    }
    
    else
        [self dataLayerHandler:self didFailToHandleDataLayerAtURL:fileURL];
}

- (void)openGeoJSONFile:(NSURL *)fileURL
{
    NSArray *items = [DSMapBoxGeoJSONParser itemsForGeoJSON:[NSString stringWithContentsOfURL:fileURL
                                                                                     encoding:NSUTF8StringEncoding
                                                                                        error:NULL]];
    
    if ([items count])
    {
        NSString *source      = [fileURL relativePath];
        NSString *filename    = [[fileURL relativePath] lastPathComponent];
        NSString *destination = [NSString stringWithFormat:@"%@/%@", [[UIApplication sharedApplication] documentsFolderPath], filename];
        
        [[NSFileManager defaultManager] copyItemAtPath:source toPath:destination error:NULL];
        
        [self layerImportAlertWithName:[fileURL lastPathComponent]];
        
        [TESTFLIGHT passCheckpoint:@"imported GeoJSON"];
    }
    
    else
        [self dataLayerHandler:self didFailToHandleDataLayerAtURL:fileURL];
}

- (void)openMBTilesFile:(NSURL *)fileURL
{
    NSString *source      = [fileURL relativePath];
    NSString *filename    = [[fileURL relativePath] lastPathComponent];
    NSString *destination = [NSString stringWithFormat:@"%@/%@", [[UIApplication sharedApplication] documentsFolderPath], filename];
    
    [[NSFileManager defaultManager] copyItemAtPath:source toPath:destination error:NULL];
    
    [self layerImportAlertWithName:[fileURL lastPathComponent]];
    
    [TESTFLIGHT passCheckpoint:@"imported MBTiles"];
}

- (IBAction)tappedLayersButton:(id)sender
{
    if ( ! layersPopover)
    {
        DSMapBoxLayerController *layerController = [[[DSMapBoxLayerController alloc] initWithNibName:nil bundle:nil] autorelease];
        
        layerController.layerManager = layerManager;
        layerController.delegate     = self;
        
        UINavigationController *wrapper = [[[UINavigationController alloc] initWithRootViewController:layerController] autorelease];
        
        layersPopover = [[UIPopoverController alloc] initWithContentViewController:wrapper];
        
        layersPopover.passthroughViews = nil;
    }

    [self manageExclusiveItem:layersPopover];

    if (layersPopover.popoverVisible)
        [layersPopover dismissPopoverAnimated:YES];
    
    else
        [layersPopover presentPopoverFromBarButtonItem:layersButton permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
}

- (IBAction)tappedClusteringButton:(id)sender
{
    [self manageExclusiveItem:sender];
    
    [TESTFLIGHT passCheckpoint:@"toggled clustering"];
    
    DSMapBoxMarkerManager *markerManager = (DSMapBoxMarkerManager *)mapView.topMostMapView.contents.markerManager;
    
    markerManager.clusteringEnabled = ! markerManager.clusteringEnabled;
    
    [self setClusteringOn:markerManager.clusteringEnabled];
}

- (IBAction)tappedHelpButton:(id)sender
{
    [TESTFLIGHT passCheckpoint:@"viewed help"];
    
    [self manageExclusiveItem:sender];
    
    DSMapBoxHelpController *helpController = [[[DSMapBoxHelpController alloc] initWithNibName:nil bundle:nil] autorelease];
    
    DSMapBoxAlphaModalNavigationController *wrapper = [[[DSMapBoxAlphaModalNavigationController alloc] initWithRootViewController:helpController] autorelease];
    
    if ( ! [[NSUserDefaults standardUserDefaults] objectForKey:@"firstRunVideoPlayed"])
    {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"firstRunVideoPlayed"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    helpController.navigationItem.title = [NSString stringWithFormat:@"%@ Help", [[NSProcessInfo processInfo] processName]];
    
    helpController.navigationItem.rightBarButtonItem = [[[DSMapBoxTintedBarButtonItem alloc] initWithTitle:@"Done"
                                                                                                    target:helpController
                                                                                                    action:@selector(tappedHelpDoneButton:)] autorelease];
    
    wrapper.modalPresentationStyle = UIModalPresentationFormSheet;
    wrapper.modalTransitionStyle   = UIModalTransitionStyleCoverVertical;
    
    [self presentModalViewController:wrapper animated:YES];
}

- (IBAction)tappedShareButton:(id)sender
{
    if ( ! shareActionSheet || ! shareActionSheet.visible)
    {
        shareActionSheet = [[UIActionSheet alloc] initWithTitle:nil
                                                       delegate:self
                                              cancelButtonTitle:nil
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:@"Email Snapshot", nil];
        
        [shareActionSheet showFromBarButtonItem:sender animated:YES];
        
        [self manageExclusiveItem:shareActionSheet];
    }
    
    else
        [shareActionSheet dismissWithClickedButtonIndex:-1 animated:YES];
}

- (void)setClusteringOn:(BOOL)clusteringOn
{
    UIButton *button;

    if ( ! clusteringButton.customView)
    {
        button = [UIButton buttonWithType:UIButtonTypeCustom];
        
        [button addTarget:self action:@selector(tappedClusteringButton:) forControlEvents:UIControlEventTouchUpInside];
        
        clusteringButton.customView = button;
    }
    
    else
        button = ((UIButton *)clusteringButton.customView);

    UIImage *stateImage = (clusteringOn ? [UIImage imageNamed:@"cluster_on.png"] : [UIImage imageNamed:@"cluster_off.png"]);

    button.bounds = CGRectMake(0, 0, stateImage.size.width, stateImage.size.height);

    [button setImage:stateImage forState:UIControlStateNormal];
}

#pragma mark -

- (void)reachabilityDidChange:(NSNotification *)notification
{
    if ([(Reachability *)[notification object] currentReachabilityStatus] == NotReachable)
    {
        for (NSURL *layerURL in [[layerManager.tileLayers filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"selected = 1"]] valueForKey:@"URL"])
        {
            if ([layerURL isEqual:kDSOpenStreetMapURL] || [layerURL isEqual:kDSMapQuestOSMURL] || [layerURL isTileStreamURL])
            {
                [self offlineAlert];
                
                return;
            }
        }
    }
}

- (void)offlineAlert
{
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Now Offline"
                                                     message:@"You are now offline. At least one active layer requires an internet connection, so it may not appear reliably."
                                                    delegate:nil
                                           cancelButtonTitle:nil
                                           otherButtonTitles:@"OK", nil] autorelease];

    [alert performSelector:@selector(show) withObject:nil afterDelay:0.0];
}

- (UIImage *)mapSnapshot
{
    // zoom to even zoom level to avoid artifacts
    //
    CGFloat oldZoom = mapView.contents.zoom;
    CGPoint center  = CGPointMake(mapView.frame.size.width / 2, mapView.frame.size.height / 2);
    
    if ((CGFloat)ceil(oldZoom) - oldZoom < 0.5)    
        [mapView.contents zoomInToNextNativeZoomAt:center];
    
    else
        [mapView.contents zoomOutToNextNativeZoomAt:center];
    
    // get full screen snapshot
    //
    UIGraphicsBeginImageContext(self.view.bounds.size);
    [self.view.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *full = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    // restore previous zoom
    //
    float factor = exp2f(oldZoom - [mapView.contents zoom]);
    [mapView.contents zoomByFactor:factor near:center];
    
    // crop out top toolbar
    //
    CGImageRef cropped = CGImageCreateWithImageInRect(full.CGImage, CGRectMake(0, 
                                                                               toolbar.frame.size.height, 
                                                                               full.size.width, 
                                                                               full.size.height - toolbar.frame.size.height));
    
    // convert & clean up
    //
    UIImage *snapshot = [UIImage imageWithCGImage:cropped];
    CGImageRelease(cropped);

    return snapshot;
}

- (void)zoomBoundsReached:(NSNotification *)notification
{
    if ( ! [[NSUserDefaults standardUserDefaults] boolForKey:@"skipWarningAboutZoom"])
    {
        if ([[NSDate date] timeIntervalSinceDate:self.lastLayerAlertDate] > 5.0)
        {
            NSString *message = [NSString stringWithFormat:@"All layers have built-in zoom limits. %@ lets you continue to zoom, but layers that don't support the current zoom level won't always appear reliably. %@ is now out of range.", [[NSProcessInfo processInfo] processName], [[notification object] valueForKeyPath:@"tileSource.shortName"]];
            
            DSMapBoxAlertView *alert = [[[DSMapBoxAlertView alloc] initWithTitle:@"Layer Zoom Exceeded"
                                                                         message:message 
                                                                        delegate:self
                                                               cancelButtonTitle:@"Don't Warn"
                                                               otherButtonTitles:@"OK", nil] autorelease];
            
            alert.context = @"zoom warning";
            
            [alert performSelector:@selector(show) withObject:nil afterDelay:0.5];
        }
    }
}

- (void)layerImportAlertWithName:(NSString *)name
{
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Layer Imported"
                                                     message:[NSString stringWithFormat:@"The new layer %@ was imported successfully. You may now find it in the layers menu.", name]
                                                    delegate:nil
                                           cancelButtonTitle:nil
                                           otherButtonTitles:@"OK", nil] autorelease];
    
    [alert show];
}

- (void)layersAdded:(NSNotification *)notification
{
    // add layers to disk
    //
    NSArray *layers = [[notification userInfo] objectForKey:@"selectedLayers"];
    
    NSMutableString *message = [NSMutableString string];
    
    for (NSDictionary *layer in layers)
    {
        [message appendString:[layer objectForKey:@"name"]];
        [message appendString:@"\n"];
        
        NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                 [layer objectForKey:@"apiScheme"], @"apiScheme",
                                 [layer objectForKey:@"apiHostname"], @"apiHostname",
                                 [layer objectForKey:@"apiPort"], @"apiPort",
                                 [layer objectForKey:@"apiPath"], @"apiPath",
                                 [layer objectForKey:@"id"], @"id",
                                 ([layer objectForKey:@"bounds"] ? [[layer objectForKey:@"bounds"] componentsJoinedByString:@","] : @""), @"bounds",
                                 ([layer objectForKey:@"center"] ? [[layer objectForKey:@"center"] componentsJoinedByString:@","] : @""), @"center",
                                 ([layer objectForKey:@"name"] ? [layer objectForKey:@"name"] : @""), @"name",
                                 ([layer objectForKey:@"attribution"] ? [layer objectForKey:@"attribution"] : @""), @"attribution",
                                 ([layer objectForKey:@"type"] ? [layer objectForKey:@"type"] : @""), @"type",
                                 ([layer objectForKey:@"version"] ? [layer objectForKey:@"version"] : @""), @"version",
                                 [layer objectForKey:@"size"], @"size",
                                 [NSNumber numberWithInt:[[layer objectForKey:@"maxzoom"] intValue]], @"maxzoom",
                                 [NSNumber numberWithInt:[[layer objectForKey:@"minzoom"] intValue]], @"minzoom",
                                 ([layer objectForKey:@"description"] ? [layer objectForKey:@"description"] : @""), @"description",
                                 [NSDate dateWithTimeIntervalSince1970:([[layer objectForKey:@"mtime"] doubleValue] / 1000)], @"mtime",
                                 ([layer objectForKey:@"basename"] ? [layer objectForKey:@"basename"] : @""), @"basename",
                                 [layer objectForKey:@"tileURL"], @"tileURL",
                                 ([layer objectForKey:@"gridURL"] ? [layer objectForKey:@"gridURL"] : @""), @"gridURL",
                                 ([layer objectForKey:@"formatter"] ? [layer objectForKey:@"formatter"] : @""), @"formatter",
                                 nil];
        
        NSString *prefsFolder = [[UIApplication sharedApplication] preferencesFolderPath];
        
        [dict writeToFile:[NSString stringWithFormat:@"%@/%@/%@.plist", prefsFolder, kTileStreamFolderName, [layer objectForKey:@"id"]] atomically:YES];
    }
    
    // animate layers into layer UI
    //
    NSArray *layerImages = [[notification userInfo] objectForKey:@"selectedImages"];
    
    NSArray *angles = [NSArray arrayWithObjects:[NSNumber numberWithInt:2], 
                                                [NSNumber numberWithInt:-3], 
                                                [NSNumber numberWithInt:0], 
                                                [NSNumber numberWithInt:-1], 
                                                [NSNumber numberWithInt:-2], 
                                                nil];

    NSMutableArray *imageViews = [NSMutableArray array];
    
    int max = [layerImages count];
    
    for (int i = 0; i < max; i++)
    {
        // create tile image view
        //
        UIImageView *imageView = [[[UIImageView alloc] initWithImage:[[layerImages objectAtIndex:i] transparentBorderImage:1]] autorelease];
        
        imageView.layer.shadowOpacity = 0.5;
        imageView.layer.shadowPath = [[UIBezierPath bezierPathWithRect:imageView.bounds] CGPath];
        imageView.layer.shadowOffset = CGSizeMake(0, 1);
        
        [self.view insertSubview:imageView aboveSubview:toolbar];
        
        // determine even spacing
        //
        int delta;
        
        if (max % 2 && i == max / 2)
            delta = 0;
        
        else if (max % 2)
            delta = ((max / 2) - i) * -50;
        
        else
            delta = (i >= (max / 2) ? (i - (max / 2) + 1) * 50 : ((max / 2) - i) * -50);
        
        // place & rotate initially
        //
        imageView.center = CGPointMake(mapView.center.x + delta, mapView.center.y);
        
        imageView.transform = CGAffineTransformMakeRotation([[angles objectAtIndex:(i % 5)] intValue] * M_PI / 180);
        
        // store reference for later
        //
        [imageViews addObject:imageView];
    }
    
    [UIView animateWithDuration:0.25
                          delay:0.0
                        options:UIViewAnimationCurveEaseInOut
                     animations:^(void)
                     {
                         // slide up from center of screen
                         //
                         for (UIView *view in imageViews)
                             view.center = CGPointMake(view.center.x, mapView.center.y - 200);
                     }
                     completion:^(BOOL finished)
                     {
                         [UIView animateWithDuration:0.25
                                               delay:0.75
                                             options:UIViewAnimationCurveEaseInOut
                                          animations:^(void)
                                          {
                                              if (max > 1)
                                              {
                                                  // play scrunching-together sound for multiple tiles
                                                  //
                                                  dispatch_delayed_ui_action(0.6, ^(void)
                                                  {
                                                      [DSSound playSoundNamed:@"paper_throw_start.wav"];
                                                  });
                                              }
                                              
                                              // move together into stack
                                              //
                                              for (UIView *view in imageViews)
                                                  view.center = CGPointMake(mapView.center.x, mapView.center.y - 200);
                                          }
                                          completion:^(BOOL finished)
                                          {
                                              // animate stack over to layers button
                                              //
                                              for (UIView *view in imageViews)
                                              {
                                                  // path
                                                  //
                                                  CGPoint startPoint = view.center;
                                                  CGPoint endPoint   = CGPointZero;
                                                  
                                                  for (UIBarButtonItem *item in toolbar.items)
                                                      if (item.action == @selector(tappedLayersButton:))
                                                          endPoint = [[[item valueForKeyPath:@"view"] valueForKeyPath:@"center"] CGPointValue];
                                                  
                                                  CGPoint controlPoint = CGPointMake(startPoint.x, startPoint.y + 100);
                                                  
                                                  UIBezierPath *arcPath = [UIBezierPath bezierPath];
                                                  
                                                  [arcPath moveToPoint:startPoint];
                                                  [arcPath addQuadCurveToPoint:endPoint controlPoint:controlPoint];
                                                  
                                                  CAKeyframeAnimation *pathAnimation = [CAKeyframeAnimation animationWithKeyPath:@"position"];
                                                  
                                                  pathAnimation.path = [arcPath CGPath];
                                                  pathAnimation.calculationMode = kCAAnimationPaced;
                                                  pathAnimation.timingFunctions = [NSArray arrayWithObject:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
                                                  
                                                  // opacity
                                                  //
                                                  CABasicAnimation *fadeAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
                                                  
                                                  [fadeAnimation setToValue:[NSNumber numberWithFloat:0.75]];
                                                  
                                                  // size
                                                  //
                                                  CABasicAnimation *sizeAnimation = [CABasicAnimation animationWithKeyPath:@"bounds.size"];
                                                  
                                                  [sizeAnimation setToValue:[NSValue valueWithCGSize:CGSizeMake(4, 4)]];
                                                  
                                                  // shadow path
                                                  //
                                                  CABasicAnimation *shadowPathAnimation = [CABasicAnimation animationWithKeyPath:@"shadowPath"];
                                                  
                                                  [shadowPathAnimation setToValue:(id)[[UIBezierPath bezierPathWithRect:CGRectMake(0, 0, 4, 4)] CGPath]];
                                                  
                                                  // shadow fade
                                                  //
                                                  CABasicAnimation *shadowFadeAnimation = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
                                                  
                                                  [shadowFadeAnimation setToValue:[NSNumber numberWithFloat:0.0]];
                                                  
                                                  // group
                                                  //
                                                  CAAnimationGroup *group = [CAAnimationGroup animation];
                                                  
                                                  group.animations = [NSArray arrayWithObjects:pathAnimation, fadeAnimation, sizeAnimation, shadowPathAnimation, shadowFadeAnimation, nil];
                                                  
                                                  group.fillMode = kCAFillModeForwards;
                                                  group.duration = 1.0;
                                                  group.beginTime = CACurrentMediaTime() + 0.5;
                                                  group.removedOnCompletion = NO;
                                                  
                                                  [CATransaction begin];
                                                  [CATransaction setCompletionBlock:^(void)
                                                  {
                                                      [view removeFromSuperview];
                                                  }];
                                                  
                                                  [view.layer addAnimation:group forKey:nil];
                                                  
                                                  [CATransaction commit];
                                              }
                                              
                                              dispatch_delayed_ui_action(1.25, ^(void)
                                              {
                                                  // play landing sound
                                                  //
                                                  [DSSound playSoundNamed:@"paper_throw_end.wav"];
                                              });
                         }];
    }];
}

- (void)checkPasteboardForURL
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"skipPasteboardURLPrompt"] != YES)
    {
        // check clipboard for supported URL
        //
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        NSURL *pasteboardURL     = nil;

        for (NSString *type in [pasteboard pasteboardTypes])
        {
            if ( ! pasteboardURL)
            {
                if ([type isEqualToString:(NSString *)kUTTypeURL])
                    pasteboardURL = (NSURL *)[pasteboard valueForPasteboardType:(NSString *)kUTTypeURL];

                else if (UTTypeConformsTo((CFStringRef)type, kUTTypeText))
                    pasteboardURL = [NSURL URLWithString:(NSString *)[pasteboard valueForPasteboardType:type]];
            }
        }
                
        if (pasteboardURL)
        {
            if ([[NSArray arrayWithObjects:@"kml", @"kmz", @"xml", @"rss", @"geojson", @"json", @"mbtiles", nil] containsObject:[pasteboardURL pathExtension]])
            {
                NSString *message = [NSString stringWithFormat:@"You have recently copied the URL %@. Would you like to import the URL into %@?", pasteboardURL, [[NSProcessInfo processInfo] processName]];
                
                DSMapBoxAlertView *alert = [[[DSMapBoxAlertView alloc] initWithTitle:@"Copied URL"
                                                                             message:message  
                                                                            delegate:self
                                                                   cancelButtonTitle:@"Don't Import"
                                                                   otherButtonTitles:@"Import", @"Don't Ask Again", nil] autorelease];
                
                alert.context = pasteboardURL;
                
                [alert show];
                
                [TESTFLIGHT passCheckpoint:@"prompted to import clipboard URL"];
            }
        }
    }
}

#pragma mark -

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if ([actionSheet isEqual:documentsActionSheet])
    {
        if (buttonIndex == actionSheet.firstOtherButtonIndex)
        {
            loadController = [[[DSMapBoxDocumentLoadController alloc] initWithNibName:nil bundle:nil] autorelease];

            UINavigationController *wrapper = [[[UINavigationController alloc] initWithRootViewController:loadController] autorelease];
            
            wrapper.navigationBar.barStyle    = UIBarStyleBlack;
            wrapper.navigationBar.translucent = YES;
            
            loadController.navigationItem.leftBarButtonItem  = [[[UIBarButtonItem alloc] initWithTitle:@"Cancel"
                                                                                                 style:UIBarButtonItemStyleBordered
                                                                                                target:self
                                                                                                action:@selector(dismissModal)] autorelease];
            
            loadController.delegate = self;
            
            wrapper.modalPresentationStyle = UIModalPresentationFullScreen;
            wrapper.modalTransitionStyle   = UIModalTransitionStyleFlipHorizontal;

            [self presentModalViewController:wrapper animated:YES];
        }
        else if (buttonIndex > -1)
        {
            saveController = [[[DSMapBoxDocumentSaveController alloc] initWithNibName:nil bundle:nil] autorelease];
            
            saveController.snapshot = [self mapSnapshot];
            
            NSUInteger i = 1;
            
            NSString *docName = nil;
            
            while ( ! docName)
            {
                if ([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/%@%@.plist", [DSMapBoxDocumentLoadController saveFolderPath], kDSSaveFileName, (i == 1 ? @"" : [NSString stringWithFormat:@" %i", i])]])
                    i++;
                
                else
                    docName = [NSString stringWithFormat:@"%@%@", kDSSaveFileName, (i == 1 ? @"" : [NSString stringWithFormat:@" %i", i])];
            }
            
            saveController.name = docName;
            
            DSMapBoxAlphaModalNavigationController *wrapper = [[[DSMapBoxAlphaModalNavigationController alloc] initWithRootViewController:saveController] autorelease];
            
            saveController.navigationItem.leftBarButtonItem  = [[[UIBarButtonItem alloc] initWithTitle:@"Cancel"
                                                                                                 style:UIBarButtonItemStyleBordered
                                                                                                target:self
                                                                                                action:@selector(dismissModal)] autorelease];
            
            saveController.navigationItem.rightBarButtonItem = [[[DSMapBoxTintedBarButtonItem alloc] initWithTitle:@"Save"
                                                                                                            target:self
                                                                                                            action:@selector(saveState:)] autorelease];
            
            wrapper.modalPresentationStyle = UIModalPresentationFormSheet;
            wrapper.modalTransitionStyle   = UIModalTransitionStyleCoverVertical;

            [self presentModalViewController:wrapper animated:YES];
        }
    }
    else if ([actionSheet isEqual:shareActionSheet])
    {
        if (buttonIndex == actionSheet.firstOtherButtonIndex)
        {
            [TESTFLIGHT passCheckpoint:@"composed snapshot from main view"];
            
            // email snapshot
            //
            if ([MFMailComposeViewController canSendMail])
            {
                MFMailComposeViewController *mailer = [[[MFMailComposeViewController alloc] init] autorelease];
                
                mailer.mailComposeDelegate = self;
                
                [mailer setSubject:@""];
                [mailer setMessageBody:@"<p>&nbsp;</p><p>Powered by <a href=\"http://mapbox.com\">MapBox</a></p>" isHTML:YES];
                
                [mailer addAttachmentData:UIImageJPEGRepresentation([self mapSnapshot], 1.0) 
                                 mimeType:@"image/jpeg"
                                 fileName:@"MapBoxSnapshot.jpg"];
                
                mailer.modalPresentationStyle = UIModalPresentationPageSheet;
                
                [self presentModalViewController:mailer animated:YES];
            }
            else
            {
                UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Mail Not Setup"
                                                                 message:@"Please setup Mail first."
                                                                delegate:nil
                                                       cancelButtonTitle:nil
                                                       otherButtonTitles:@"OK", nil] autorelease];
                
                [alert show];
            }
        }
    }
}

#pragma mark -

- (void)documentLoadController:(DSMapBoxDocumentLoadController *)controller didLoadDocumentWithName:(NSString *)name
{
    // put up dimmer & spinner (these will release when the load controller modal goes away)
    //
    UIView *dimmer = [[[UIView alloc] initWithFrame:controller.view.frame] autorelease];
    
    dimmer.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];
    
    [controller.view addSubview:dimmer];
    
    UIActivityIndicatorView *spinner = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge] autorelease];
    
    [spinner startAnimating];
    
    spinner.center = dimmer.center;
    
    [dimmer addSubview:spinner];
    
    // actually load state
    //
    dispatch_delayed_ui_action(0.0, ^(void) { [self restoreState:name]; });
}

- (void)documentLoadController:(DSMapBoxDocumentLoadController *)controller wantsToSaveDocumentWithName:(NSString *)name
{
    [self saveState:name];
    
    [TESTFLIGHT passCheckpoint:@"saved document from main view"];
}

#pragma mark -

- (void)dataLayerHandler:(id)handler didUpdateTileLayers:(NSArray *)activeTileLayers
{
    // update attributions - first, remove empties
    //
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF != '' AND SELF != %@", [NSNull null]];
    
    NSArray *allAttributions = [[activeTileLayers valueForKey:@"attribution"] filteredArrayUsingPredicate:predicate];
    
    // de-dupe
    //
    NSSet *uniqueAttributions = [NSSet setWithArray:allAttributions];
    
    // update label
    //
    attributionLabel.text = [[uniqueAttributions allObjects] componentsJoinedByString:@" "];
}

- (void)dataLayerHandler:(id)handler didUpdateDataLayers:(NSArray *)activeDataLayers
{
    if ([activeDataLayers count] > 0 && ! [toolbar.items containsObject:clusteringButton])
    {
        NSMutableArray *newItems = [NSMutableArray arrayWithArray:toolbar.items];

        [newItems insertObject:clusteringButton atIndex:([newItems count] - 1)];

        [toolbar setItems:newItems animated:YES];
    }
    else if ([activeDataLayers count] == 0 && [toolbar.items containsObject:clusteringButton])
    {
        NSMutableArray *newItems = [NSMutableArray arrayWithArray:toolbar.items];

        [newItems removeObject:clusteringButton];

        [toolbar setItems:newItems animated:YES];
    }
}

- (void)dataLayerHandler:(id)handler didFailToHandleDataLayerAtURL:(NSURL *)layerURL
{
    self.badParseURL = layerURL;
    
    NSString *message = [NSString stringWithFormat:@"%@ was unable to handle the layer file. Please contact us with a copy of the file in order to request support for it.", [[NSProcessInfo processInfo] processName]];
    
    DSMapBoxAlertView *alert = [[[DSMapBoxAlertView alloc] initWithTitle:@"Layer Problem"
                                                                 message:message
                                                                delegate:self
                                                       cancelButtonTitle:@"Don't Send"
                                                       otherButtonTitles:@"Send Mail", nil] autorelease];
    
    alert.context = @"layer problem";
    
    [alert show];
}

#pragma mark -

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    DSMapBoxAlertView *customAlertView = (DSMapBoxAlertView *)alertView;
    
    if ([customAlertView.context isKindOfClass:[NSString class]] && [customAlertView.context isEqualToString:@"layer problem"])
    {
        if (buttonIndex == alertView.firstOtherButtonIndex)
        {
            if ([MFMailComposeViewController canSendMail])
            {
                MFMailComposeViewController *mailer = [[[MFMailComposeViewController alloc] init] autorelease];
                
                mailer.mailComposeDelegate = self;
                
                [mailer setToRecipients:[NSArray arrayWithObject:KSupportEmail]];
                [mailer setMessageBody:@"<em>Please provide any additional details about this file or about the error you encountered here.</em>" isHTML:YES];
                
                if ([[self.badParseURL pathExtension] isEqualToString:@"kml"])
                {
                    [mailer setSubject:@"Problem KML file"];
                    
                    [mailer addAttachmentData:[NSData dataWithContentsOfURL:self.badParseURL]                       
                                     mimeType:@"application/vnd.google-earth.kml+xml" 
                                     fileName:[[self.badParseURL absoluteString] lastPathComponent]];
                }
                else if ([[self.badParseURL pathExtension] isEqualToString:@"kmz"])
                {
                    [mailer setSubject:@"Problem KMZ file"];
                    
                    [mailer addAttachmentData:[NSData dataWithContentsOfURL:self.badParseURL]                      
                                     mimeType:@"application/vnd.google-earth.kmz" 
                                     fileName:[[self.badParseURL absoluteString] lastPathComponent]];
                }
                else if ([[self.badParseURL pathExtension] isEqualToString:@"rss"] || [[self.badParseURL pathExtension] hasSuffix:@".xml"])
                {
                    [mailer setSubject:@"Problem RSS file"];
                    
                    [mailer addAttachmentData:[NSData dataWithContentsOfURL:self.badParseURL]                       
                                     mimeType:@"application/rss+xml" 
                                     fileName:[[self.badParseURL absoluteString] lastPathComponent]];
                }
                else if ([[self.badParseURL pathExtension] isEqualToString:@"geojson"] || [[self.badParseURL pathExtension] hasSuffix:@".json"])
                {
                    [mailer setSubject:@"Problem GeoJSON file"];
                    
                    [mailer addAttachmentData:[NSData dataWithContentsOfURL:self.badParseURL]                       
                                     mimeType:@"text/plain" 
                                     fileName:[[self.badParseURL absoluteString] lastPathComponent]];
                }
                else
                {
                    [mailer setSubject:@"Problem file"];
                    
                    [mailer addAttachmentData:[NSData dataWithContentsOfURL:self.badParseURL]                       
                                     mimeType:@"application/octet-stream" 
                                     fileName:[[self.badParseURL absoluteString] lastPathComponent]];
                }
                
                mailer.modalPresentationStyle = UIModalPresentationPageSheet;
                
                [self presentModalViewController:mailer animated:YES];
                
                [TESTFLIGHT passCheckpoint:@"prompted to report layer problem"];
            }
            else
            {
                UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Mail Not Setup"
                                                                 message:@"Please setup Mail first."
                                                                delegate:nil
                                                       cancelButtonTitle:nil
                                                       otherButtonTitles:@"OK", nil] autorelease];
                
                [alert show];
            }
        }
    }
    else if ([customAlertView.context isKindOfClass:[NSString class]] && [customAlertView.context isEqualToString:@"zoom warning"])
    {
        self.lastLayerAlertDate = [NSDate date];
        
        if (buttonIndex == alertView.cancelButtonIndex)
        {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"skipWarningAboutZoom"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }
    else if ([customAlertView.context isKindOfClass:[NSURL class]])
    {
        if (buttonIndex == customAlertView.firstOtherButtonIndex)
        {
            [TESTFLIGHT passCheckpoint:@"imported clipboard URL"];

            [[UIPasteboard generalPasteboard] setValue:nil forPasteboardType:(NSString *)kUTTypeURL];
            
            [(MapBoxAppDelegate *)[[UIApplication sharedApplication] delegate] openExternalURL:(NSURL *)customAlertView.context];
        }
        else if (buttonIndex == customAlertView.firstOtherButtonIndex + 1)
        {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"skipPasteboardURLPrompt"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }
}

#pragma mark -

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{
    switch (result)
    {
        case MFMailComposeResultFailed:
            
            [self dismissModalViewControllerAnimated:NO];
            
            UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Mail Failed"
                                                             message:@"There was a problem sending the mail."
                                                            delegate:nil
                                                   cancelButtonTitle:nil
                                                   otherButtonTitles:@"OK", nil] autorelease];
            
            [alert show];
            
            break;
            
        default:
            
            [self dismissModalViewControllerAnimated:YES];
    }
}

#pragma mark -

- (void)zoomToLayer:(NSDictionary *)layer
{
    NSURL *layerURL = [layer objectForKey:@"URL"];
    
    id source = nil;
    
    if ([layerURL isMBTilesURL])
        source = [[[RMMBTilesTileSource alloc] initWithTileSetURL:layerURL] autorelease];

    else if ([layerURL isTileStreamURL])
        source = [[[RMTileStreamSource alloc] initWithReferenceURL:layerURL] autorelease];
    
    if ( ! source)
        return;
    
    mapView.contents.zoom = ([source minZoomNative] >= kLowerZoomBounds ? [source minZoomNative] : kLowerZoomBounds);
    
    if ( ! [source coversFullWorld])
    {
        RMSphericalTrapezium bbox = [source latitudeLongitudeBoundingBox];
        
        CLLocationDegrees lon, lat;
        
        lon = (bbox.northeast.longitude + bbox.southwest.longitude) / 2;
        lat = (bbox.northeast.latitude  + bbox.southwest.latitude)  / 2;
        
        [mapView.contents moveToLatLong:CLLocationCoordinate2DMake(lat, lon)];
    }
}

- (void)presentAddLayerHelper
{
    if ([reachability currentReachabilityStatus] == NotReachable)
    {
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"No Internet Connection"
                                                         message:@"Adding a layer requires an active internet connection."
                                                        delegate:nil
                                               cancelButtonTitle:nil
                                               otherButtonTitles:@"OK", nil] autorelease];
        
        [alert show];
        
        return;
    }
    
    // dismiss layer UI
    //
    [self tappedLayersButton:self];

    DSMapBoxLayerAddTileStreamAlbumController *albumController = [[[DSMapBoxLayerAddTileStreamAlbumController alloc] initWithNibName:nil bundle:nil] autorelease];
    DSMapBoxAlphaModalNavigationController *wrapper  = [[[DSMapBoxAlphaModalNavigationController alloc] initWithRootViewController:albumController] autorelease];
    
    wrapper.modalPresentationStyle = UIModalPresentationFormSheet;
    wrapper.modalTransitionStyle   = UIModalTransitionStyleCoverVertical;

    [self presentModalViewController:wrapper animated:YES];
}

@end
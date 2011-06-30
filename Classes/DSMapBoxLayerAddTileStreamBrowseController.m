//
//  DSMapBoxLayerAddTileStreamBrowseController.m
//  MapBoxiPad
//
//  Created by Justin R. Miller on 5/17/11.
//  Copyright 2011 Code Sorcery Workshop. All rights reserved.
//

#import "DSMapBoxLayerAddTileStreamBrowseController.h"

#import "MapBoxConstants.h"

#import "DSMapBoxLayerAddTileView.h"
#import "DSMapBoxLayerAddPreviewController.h"
#import "DSMapBoxLayerAddNavigationController.h"

#import "JSONKit.h"

#import "RMTile.h"

#import <CoreLocation/CoreLocation.h>

NSString *const DSMapBoxLayersAdded = @"DSMapBoxLayersAdded";

@implementation DSMapBoxLayerAddTileStreamBrowseController

@synthesize serverURL;

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // setup state
    //
    layers = [[NSArray array] retain];
    
    selectedLayers = [[NSMutableArray array] retain];
    selectedImages = [[NSMutableArray array] retain];
    
    // setup nav bar
    //
    self.navigationItem.title = @"Browse Server";
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:@"Add Layer"
                                                                               style:UIBarButtonItemStyleDone
                                                                              target:self
                                                                              action:@selector(tappedDoneButton:)] autorelease];

    self.navigationItem.rightBarButtonItem.enabled = NO;
    
    // setup progress indication
    //
    [spinner startAnimating];
    
    helpLabel.hidden       = YES;
    tileScrollView.hidden  = YES;
    tilePageControl.hidden = YES;
    
    // fire off layer list request
    //
    NSString *fullURLString = [NSString stringWithFormat:@"%@%@", self.serverURL, kTileStreamAPIPath];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:fullURLString]];
    
    [[NSURLConnection alloc] initWithRequest:request delegate:self];
}

- (void)dealloc
{
    [layers release];
    [selectedLayers release];
    [selectedImages release];

    [serverURL release];
    
    [super dealloc];
}


#pragma mark -

- (void)tappedDoneButton:(id)sender
{
    [self.parentViewController dismissModalViewControllerAnimated:YES];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:DSMapBoxLayersAdded 
                                                        object:self 
                                                      userInfo:[NSDictionary dictionaryWithObjectsAndKeys:selectedLayers, @"selectedLayers",
                                                                                                          selectedImages, @"selectedImages", 
                                                                                                          nil]];
}

- (void)tileView:(DSMapBoxLayerAddTileView *)tileView selectionDidChange:(BOOL)selected
{
    // get layer & image in question
    //
    NSDictionary *layer = [layers objectAtIndex:tileView.tag];
    UIImage *layerImage = tileView.image;
    
    // update selection
    //
    if ([selectedLayers containsObject:layer])
    {
        [selectedLayers removeObject:layer];
        [selectedImages removeObject:layerImage];
    }
    else
    {
        [selectedLayers addObject:layer];
        [selectedImages addObject:layerImage];
    }
    
    // enable/disable action button
    //
    if ([selectedLayers count])
        self.navigationItem.rightBarButtonItem.enabled = YES;
    
    else
        self.navigationItem.rightBarButtonItem.enabled = NO;
    
    // modify action button title
    //
    if ([selectedLayers count] > 1)
        self.navigationItem.rightBarButtonItem.title = [NSString stringWithFormat:@"Add %i Layers", [selectedLayers count]];
    
    else
        self.navigationItem.rightBarButtonItem.title = @"Add Layer";
}

- (void)tileViewWantsToShowPreview:(DSMapBoxLayerAddTileView *)tileView
{
    // tap on top-right "preview" corner
    //
    DSMapBoxLayerAddPreviewController *preview = [[[DSMapBoxLayerAddPreviewController alloc] initWithNibName:nil bundle:nil] autorelease];
    
    NSDictionary *layer = [layers objectAtIndex:tileView.tag];
    
    preview.info = [NSDictionary dictionaryWithObjectsAndKeys:
                       [layer objectForKey:@"tileScheme"], @"tileScheme",
                       [layer objectForKey:@"tileHostname"], @"tileHostname", 
                       [layer objectForKey:@"tilePort"], @"tilePort", 
                       [layer objectForKey:@"tilePath"], @"tilePath", 
                       [NSNumber numberWithInt:[[layer objectForKey:@"minzoom"] intValue]], @"minzoom", 
                       [NSNumber numberWithInt:[[layer objectForKey:@"maxzoom"] intValue]], @"maxzoom", 
                       [layer objectForKey:@"id"], @"id", 
                       [layer objectForKey:@"version"], @"version", 
                       [layer objectForKey:@"name"], @"name", 
                       [layer objectForKey:@"description"], @"description", 
                       [layer objectForKey:@"center"], @"center",
                       nil];
    
    DSMapBoxLayerAddNavigationController *wrapper = [[[DSMapBoxLayerAddNavigationController alloc] initWithRootViewController:preview] autorelease];
    
    wrapper.navigationBar.translucent = YES;
    
    wrapper.modalPresentationStyle = UIModalPresentationFullScreen;
    wrapper.modalTransitionStyle   = UIModalTransitionStyleCrossDissolve;
    
    [self presentModalViewController:wrapper animated:YES];
}

#pragma mark -

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    // TODO: detect if offline and/or retry
    //
    NSLog(@"%@", error);
    
    [spinner stopAnimating];
    
    [connection autorelease];
    
    [receivedData release];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    receivedData = [[NSMutableData data] retain];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [receivedData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [spinner stopAnimating];
    
    [connection autorelease];
    
    id newLayers = [receivedData mutableObjectFromJSONData];
    
    [receivedData release];
    
    // TODO: what if no layers? 
    //
    if (newLayers && [newLayers isKindOfClass:[NSMutableArray class]])
    {
        helpLabel.hidden       = NO;
        tileScrollView.hidden  = NO;
        tilePageControl.hidden = NO;
        
        NSMutableArray *imagesToDownload = [NSMutableArray array];
        
        for (int i = 0; i < [newLayers count]; i++)
        {
            NSMutableDictionary *layer = [NSMutableDictionary dictionaryWithDictionary:[newLayers objectAtIndex:i]];
            
            // determine center tile to download
            //
            CLLocationCoordinate2D center = CLLocationCoordinate2DMake([[[layer objectForKey:@"center"] objectAtIndex:1] floatValue], 
                                                                       [[[layer objectForKey:@"center"] objectAtIndex:0] floatValue]);
            
            int tileZoom = [[[layer objectForKey:@"center"] objectAtIndex:2] intValue];
            
            int tileX = (int)(floor((center.longitude + 180.0) / 360.0 * pow(2.0, tileZoom)));
            int tileY = (int)(floor((1.0 - log(tan(center.latitude * M_PI / 180.0) + 1.0 / \
                                               cos(center.latitude * M_PI / 180.0)) / M_PI) / 2.0 * pow(2.0, tileZoom)));
            
            tileY = pow(2.0, tileZoom) - tileY - 1.0;
            
            RMTile tile = {
                .zoom = tileZoom,
                .x    = tileX,
                .y    = tileY,
            };
            
            NSURL *tileURL;
            
            if ([layer objectForKey:@"host"] && [[layer objectForKey:@"host"] isKindOfClass:[NSArray class]])
                tileURL = [NSURL URLWithString:[[layer objectForKey:@"host"] lastObject]];
            
            else
                tileURL = self.serverURL;
            
            if ( ! [[tileURL absoluteString] hasSuffix:@"/"])
                tileURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/", tileURL]];
            
            NSURL *imageURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@1.0.0/%@/%d/%d/%d.png", 
                                                       tileURL, [layer objectForKey:@"id"], tile.zoom, tile.x, tile.y]];
            
            [imagesToDownload addObject:imageURL];
            
            // update layer for server-wide variables
            //
            [layer setValue:[self.serverURL scheme]                                                       forKey:@"apiScheme"];
            [layer setValue:[self.serverURL host]                                                         forKey:@"apiHostname"];
            [layer setValue:([self.serverURL port] ? [self.serverURL port] : [NSNumber numberWithInt:80]) forKey:@"apiPort"];
            [layer setValue:([self.serverURL path] ? [self.serverURL path] : @"")                         forKey:@"apiPath"];
            
            [layer setValue:[tileURL scheme]                                                forKey:@"tileScheme"];
            [layer setValue:[tileURL host]                                                  forKey:@"tileHostname"];
            [layer setValue:([tileURL port] ? [tileURL port] : [NSNumber numberWithInt:80]) forKey:@"tilePort"];
            [layer setValue:([tileURL path] ? [tileURL path] : @"")                         forKey:@"tilePath"];
            
            [newLayers replaceObjectAtIndex:i withObject:layer];
        }
        
        [layers release];
        
        layers = [[NSArray arrayWithArray:newLayers] retain];
        
        // layout preview tiles
        //
        int pageCount = ([layers count] / 9) + 1;
        
        tileScrollView.contentSize = CGSizeMake((tileScrollView.frame.size.width * pageCount), tileScrollView.frame.size.height);
        
        tilePageControl.numberOfPages = pageCount;

        for (int i = 0; i < pageCount; i++)
        {
            UIView *containerView = [[[UIView alloc] initWithFrame:CGRectMake(i * tileScrollView.frame.size.width, 0, tileScrollView.frame.size.width, tileScrollView.frame.size.height)] autorelease];
            
            containerView.backgroundColor = [UIColor clearColor];
            
            for (int j = 0; j < 9; j++)
            {
                int index = i * 9 + j;
                
                if (index < [layers count])
                {
                    int row = j / 3;
                    int col = j - (row * 3);

                    CGFloat x;
                    
                    if (col == 0)
                        x = 10;
                    
                    else if (col == 1)
                        x = containerView.frame.size.width / 2 - 74;
                    
                    else if (col == 2)
                        x = containerView.frame.size.width - 148 - 10;
                    
                    DSMapBoxLayerAddTileView *tileView = [[[DSMapBoxLayerAddTileView alloc] initWithFrame:CGRectMake(x, row * 158 + 10, 148, 148) 
                                                                                                 imageURL:[imagesToDownload objectAtIndex:index]
                                                                                                labelText:[[layers objectAtIndex:index] valueForKey:@"name"]] autorelease];
                    
                    tileView.delegate = self;
                    tileView.tag = index;
                    
                    [containerView addSubview:tileView];
                }
            }
            
            [tileScrollView addSubview:containerView];
        }
    }
}

#pragma mark -

// TODO: if scrolling too fast, doesn't update
//
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    tilePageControl.currentPage = (int)floorf(scrollView.contentOffset.x / scrollView.frame.size.width);
}

@end
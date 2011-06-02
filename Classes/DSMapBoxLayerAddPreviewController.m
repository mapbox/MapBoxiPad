    //
//  DSMapBoxLayerAddPreviewController.m
//  MapBoxiPad
//
//  Created by Justin R. Miller on 5/18/11.
//  Copyright 2011 Code Sorcery Workshop. All rights reserved.
//

#import "DSMapBoxLayerAddPreviewController.h"

#import "DSMapView.h"
#import "RMTileStreamSource.h"
#import "DSMapBoxTileSetManager.h"
#import "DSMapContents.h"

@implementation DSMapBoxLayerAddPreviewController

@synthesize info;

 // The designated initializer.  Override if you create the controller programmatically and want to perform customization that is not appropriate for viewDidLoad.
/*
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization.
    }
    return self;
}
*/

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    NSArray *centerParts = [info objectForKey:@"center"];
    
    
    CLLocationCoordinate2D center = CLLocationCoordinate2DMake([[centerParts objectAtIndex:1] floatValue], [[centerParts objectAtIndex:0] floatValue]);
    
    
    
    
    RMTileStreamSource *source = [[[RMTileStreamSource alloc] initWithInfo:info] autorelease];
    
    [[[DSMapContents alloc] initWithView:mapView 
                              tilesource:source
                            centerLatLon:center
                               zoomLevel:[[centerParts objectAtIndex:2] floatValue]
                            maxZoomLevel:[source maxZoom]
                            minZoomLevel:[source minZoom]
                         backgroundImage:nil] autorelease];
    
    mapView.enableRotate = NO;
    mapView.deceleration = NO;
    
    mapView.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"loading.png"]];
    
    
    
    
    
    
    
}


- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    // Overriden to allow any orientation.
    return YES;
}


- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc. that aren't in use.
}


- (void)viewDidUnload {
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}


- (void)dealloc {
    [info release];
    
    [super dealloc];
}


@end

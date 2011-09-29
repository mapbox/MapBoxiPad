//
//  DSMapBoxMarkerCluster.m
//  MapBoxiPad
//
//  Created by Justin R. Miller on 8/5/10.
//  Copyright 2010 Development Seed. All rights reserved.
//

#import "DSMapBoxMarkerCluster.h"
#import "RMMarker.h"

@interface DSMapBoxMarkerCluster (DSMapBoxMarkerClusterPrivate)

- (void)recalculateCenter;

@end

#pragma mark -

@implementation DSMapBoxMarkerCluster

@synthesize markers;
@synthesize center;

- (id)init
{
    self = [super init];
    
    if (self != nil)
    {
        markers = [[NSArray array] retain];

        center.latitude  = 0.0;
        center.longitude = 0.0;
    }

    return self;
}

- (void)dealloc
{
    [markers release];
    
    [super dealloc];
}

#pragma mark -

- (void)addMarker:(RMMarker *)marker
{
    NSMutableArray *mutableMarkers = [NSMutableArray arrayWithArray:self.markers];
    
    [mutableMarkers addObject:marker];
    
    [markers release];
    markers = [[NSArray arrayWithArray:mutableMarkers] retain];
    
    [self recalculateCenter];
}

- (void)removeMarker:(RMMarker *)marker
{
    NSMutableArray *mutableMarkers = [NSMutableArray arrayWithArray:self.markers];
    
    [mutableMarkers removeObject:marker];
    
    [markers release];
    markers = [[NSArray arrayWithArray:mutableMarkers] retain];
    
    [self recalculateCenter];
}

#pragma mark -

- (void)recalculateCenter
{
    // TODO: actually recalculate center amongst current points instead of just taking first one
    
    if ([markers count])
    {
        NSDictionary *data = (NSDictionary *)[[markers objectAtIndex:0] data];
        
        center.latitude  = ((CLLocation *)[data objectForKey:@"location"]).coordinate.latitude;
        center.longitude = ((CLLocation *)[data objectForKey:@"location"]).coordinate.longitude;
    }
}

@end
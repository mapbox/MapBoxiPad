//
//  DSMapBoxMarkerManager.m
//  MapBoxiPad
//
//  Created by Justin R. Miller on 8/4/10.
//  Copyright 2010 Development Seed. All rights reserved.
//

#import "DSMapBoxMarkerManager.h"
#import "DSMapBoxMarkerCluster.h"

#import "SimpleKML_UIImage.h"
#import "SimpleKMLPlacemark.h"

#import <CoreLocation/CoreLocation.h>

#import "RMProjection.h"
#import "RMMercatorToScreenProjection.h"
#import "RMLayerCollection.h"

#define kDSMapBoxMarkerClusterPixels 50.0f
#define kDSClusterAlpha               0.7f

@interface DSMapBoxMarkerManager ()

- (void)addBaseMarker:(RMMarker *)marker AtLatLong:(CLLocationCoordinate2D)point;
- (void)clusterMarker:(RMMarker *)marker inClusters:(NSMutableArray * __strong *)inClusters;
- (void)redrawClusters;

@end

#pragma mark -

@implementation DSMapBoxMarkerManager

@synthesize clusteringEnabled;
@synthesize clusters;

- (id)initWithContents:(RMMapContents *)mapContents
{
    self = [super initWithContents:mapContents];
    
    if (self != nil)
    {
        clusteringEnabled = YES;
        
        clusters = [NSMutableArray array];
    }
    
    return self;
}

#pragma mark -

- (void)setClusteringEnabled:(BOOL)flag
{
    if (flag == clusteringEnabled)
        return;
    
    clusteringEnabled = flag;
    
    [self recalculateClusters];
}

- (NSArray *)clusters
{
    return [NSArray arrayWithArray:clusters];
}

#pragma mark -

- (void)removeMarkers
{
    NSArray *nonMarkers = [[self markers] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"NOT SELF isKindOfClass:%@", [RMMarker class]]];
    NSArray *allMarkers = [NSArray arrayWithArray:[self markers]];
    
    [allMarkers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    
    [[contents overlay] setSublayers:nonMarkers];
}

- (void)addBaseMarker:(RMMarker *)marker AtLatLong:(CLLocationCoordinate2D)point
{
    // this is just like super's, but allows us to insert a marker as the first sublayer
    //
    RMProjectedPoint projectedPoint = [[contents projection] latLongToPoint:point];
    
    [marker setAffineTransform:rotationTransform];
    [marker setProjectedLocation:projectedPoint];
    [marker setPosition:[[contents mercatorToScreenProjection] projectXYPoint:projectedPoint]];
    [[contents overlay] insertSublayer:marker atIndex:0];
}

- (void)addMarker:(RMMarker *)marker AtLatLong:(CLLocationCoordinate2D)point
{
    [self addMarker:marker AtLatLong:point recalculatingImmediately:YES];
}

- (void)addMarker:(RMMarker *)marker AtLatLong:(CLLocationCoordinate2D)point recalculatingImmediately:(BOOL)flag
{
    [self clusterMarker:marker inClusters:&clusters];
    
    if (flag)
        [self redrawClusters];
}

- (void)removeMarkersAndClusters
{
    [clusters removeAllObjects];

    [self removeMarkers];
}

- (void)removeMarker:(RMMarker *)marker
{
    [self removeMarker:marker recalculatingImmediately:YES];
}

- (void)removeMarker:(RMMarker *)marker recalculatingImmediately:(BOOL)flag
{
    for (DSMapBoxMarkerCluster *cluster in clusters)
        if ([[cluster markers] containsObject:marker])
            [cluster removeMarker:marker];
    
    [super removeMarker:marker];
    
    if (flag)
        [self recalculateClusters];
}

- (void)removeMarkers:(NSArray *)markers
{
    for (RMMarker *marker in markers)
        [self removeMarker:marker recalculatingImmediately:NO];
    
    [self recalculateClusters];
}

- (void)moveMarker:(RMMarker *)marker AtLatLon:(RMLatLong)point
{
    NSAssert(self.clusteringEnabled == NO, @"Moving markers is unsupported when clustering is enabled");
    
    [super moveMarker:marker AtLatLon:point];
}

- (void)moveMarker:(RMMarker *)marker AtXY:(CGPoint)point
{
    NSAssert(self.clusteringEnabled == NO, @"Moving markers is unsupported when clustering is enabled");
    
    [super moveMarker:marker AtXY:point];
}

#pragma mark -

- (void)clusterMarker:(RMMarker *)marker inClusters:(NSMutableArray * __strong *)inClusters
{
    NSAssert(*inClusters, @"Invalid clusters passed to cluster routine");
    
    if (self.clusteringEnabled)
    {
        CGFloat threshold = [contents.mercatorToScreenProjection metersPerPixel] * kDSMapBoxMarkerClusterPixels;
        
        NSDictionary *data = (NSDictionary *)marker.data;
        
        NSAssert([data objectForKey:@"location"], @"RMMarker must include location data for clustering");
        
        RMLatLong point = ((CLLocation *)[data objectForKey:@"location"]).coordinate;
        
        CLLocation *markerLocation = [[CLLocation alloc] initWithLatitude:point.latitude longitude:point.longitude];
        
        BOOL clustered = NO;
        
        for (DSMapBoxMarkerCluster *cluster in *inClusters)
        {
            CLLocation *clusterLocation = [[CLLocation alloc] initWithLatitude:cluster.center.latitude longitude:cluster.center.longitude];
            
            if ([clusterLocation distanceFromLocation:markerLocation] <= threshold)
            {
                [cluster addMarker:marker];
                
                clustered = YES;
                
                break;
            }
        }
        
        if ( ! clustered)
        {
            DSMapBoxMarkerCluster *cluster = [[DSMapBoxMarkerCluster alloc] init];
            
            [cluster addMarker:marker];
            
            [*inClusters addObject:cluster];
        }
    }
    else
    {
        DSMapBoxMarkerCluster *cluster = [[DSMapBoxMarkerCluster alloc] init];
        
        [cluster addMarker:marker];
        
        [*inClusters addObject:cluster];
    }
}

- (void)recalculateClusters
{
    NSMutableArray *newClusters = [NSMutableArray array];
    
    for (DSMapBoxMarkerCluster *cluster in clusters)
        for (RMMarker *marker in [cluster markers])
            [self clusterMarker:marker inClusters:&newClusters];
    
    [clusters setArray:newClusters];
    
    [self redrawClusters];
}

- (void)redrawClusters
{
    [self removeMarkers];

    NSUInteger count = 0;
    
    for (DSMapBoxMarkerCluster *cluster in clusters)
        count += [[cluster markers] count];
    
    if ([clusters count] == count)
    {
        // no need to cluster; cluster count equals marker count
        //
        for (DSMapBoxMarkerCluster *cluster in clusters)
            for (RMMarker *marker in [cluster markers])
                [super addMarker:marker AtLatLong:((CLLocation *)[((NSDictionary *)marker.data) objectForKey:@"location"]).coordinate];
    }
    else
    {
        // get largest cluster marker count
        //
        NSUInteger maxMarkerCount = 0;
        
        for (DSMapBoxMarkerCluster *cluster in clusters)
            if ([[cluster markers] count] > maxMarkerCount)
                maxMarkerCount = [[cluster markers] count];
        
        NSMutableArray *clusterMarkers = [NSMutableArray array];
        
        for (DSMapBoxMarkerCluster *cluster in clusters)
        {
            RMMarker *marker;
            
            NSString *labelText;
            NSString *touchLabelText;
            
            // add marker for cluster if multiple markers
            //
            if ([[cluster markers] count] > 1)
            {
                CGFloat size = 44.0 + (kDSMapBoxMarkerClusterPixels * (((CGFloat)[[cluster markers] count]) / (CGFloat)maxMarkerCount));

                // TODO: allow for use of other images?
                //
                UIImage *image = [[[UIImage imageNamed:@"circle.png"] imageWithAlphaComponent:kDSClusterAlpha] imageWithWidth:size height:size];
                
                marker = [[RMMarker alloc] initWithUIImage:image];
                
                labelText      = [NSString stringWithFormat:@"%i",        [[cluster markers] count]];
                touchLabelText = [NSString stringWithFormat:@"%i Points", [[cluster markers] count]];
                
                // build up summary of clustered points
                //
                NSMutableArray *descriptions = [NSMutableArray array];
                
                for (RMMarker *clusterMarker in [cluster markers])
                {
                    NSDictionary *clusterMarkerData = ((NSDictionary *)clusterMarker.data);
                    
                    if ([clusterMarkerData objectForKey:@"placemark"])
                    {
                        SimpleKMLPlacemark *placemark = (SimpleKMLPlacemark *)[clusterMarkerData objectForKey:@"placemark"];
                        
                        [descriptions addObject:placemark.name];
                    }

                    else if ([clusterMarkerData objectForKey:@"title"])
                        [descriptions addObject:[clusterMarkerData objectForKey:@"title"]];
                }
                
                [descriptions sortUsingSelector:@selector(compare:)];
                
                // build the cluster marker
                //
                CLLocation *center = [[CLLocation alloc] initWithLatitude:cluster.center.latitude longitude:cluster.center.longitude];
                
                marker.data = [NSDictionary dictionaryWithObjectsAndKeys:touchLabelText,                                     @"title",
                                                                         [descriptions componentsJoinedByString:@", "],      @"description",
                                                                         [NSNumber numberWithInt:[[cluster markers] count]], @"count",
                                                                         center,                                             @"location",
                                                                         [NSNumber numberWithBool:YES],                      @"isCluster",
                                                                         nil];
                
                [marker changeLabelUsingText:labelText
                                        font:[RMMarker defaultFont]
                             foregroundColor:[UIColor whiteColor]
                             backgroundColor:[UIColor clearColor]];
                
                // store up clusters for a moment so we can sort them
                //
                [clusterMarkers addObject:marker];
            }

            // otherwise add marker (the cluster's only) directly
            //
            else
            {
                marker = [[cluster markers] lastObject];

                [super addMarker:marker AtLatLong:((CLLocation *)[((NSDictionary *)marker.data) objectForKey:@"location"]).coordinate];
            }
        }
        
        // sort cluster markers by increasing size
        //
        if ([clusterMarkers count])
            [clusterMarkers sortUsingDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"data.count.intValue" ascending:YES]]];
        
        // finally add clusters to map, in order, under all other path layers
        //
        for (RMMarker *clusterMarker in clusterMarkers)
            [self addBaseMarker:clusterMarker AtLatLong:((CLLocation *)[((NSDictionary *)clusterMarker.data) objectForKey:@"location"]).coordinate];
    }
}

- (void)takeClustersFromMarkerManager:(DSMapBoxMarkerManager *)markerManager
{
    NSArray *clustersToTake = [markerManager clusters];
    [markerManager removeMarkersAndClusters];
    [clusters setArray:clustersToTake];
    self.clusteringEnabled = markerManager.clusteringEnabled;
    
    [self recalculateClusters];
}

@end
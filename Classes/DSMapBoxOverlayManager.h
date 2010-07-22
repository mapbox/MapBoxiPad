//
//  DSMapBoxOverlayManager.h
//  MapBoxiPadDemo
//
//  Created by Justin R. Miller on 7/8/10.
//  Copyright 2010 Code Sorcery Workshop. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "RMMapView.h"
#import "RMLatLong.h"

#define kPlacemarkAlpha 0.7f

@class RMMapView;
@class SimpleKML;

@interface DSMapBoxOverlayManager : NSObject <RMMapViewDelegate, UIPopoverControllerDelegate>
{
    RMMapView *mapView;
    NSMutableArray *overlays;
    IBOutlet UIView *stripeView;
    IBOutlet UILabel *stripeViewLabel;
    NSMutableDictionary *lastMarkerInfo;
    NSTimer *animationTimer;
}

- (id)initWithMapView:(RMMapView *)inMapView;
- (RMSphericalTrapezium)addOverlayForKML:(SimpleKML *)kml;
- (RMSphericalTrapezium)addOverlayForGeoRSS:(NSString *)rss;
- (void)removeAllOverlays;
- (void)removeOverlayWithSource:(NSString *)source;
- (NSArray *)overlays;

@end
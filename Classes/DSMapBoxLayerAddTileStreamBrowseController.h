//
//  DSMapBoxLayerAddTileStreamBrowseController.h
//  MapBoxiPad
//
//  Created by Justin R. Miller on 5/17/11.
//  Copyright 2011 Development Seed. All rights reserved.
//

#import "DSMapBoxLayerAddTileView.h"

#import "ASIHTTPRequestDelegate.h"

extern NSString *const DSMapBoxLayersAdded;

@interface DSMapBoxLayerAddTileStreamBrowseController : UIViewController <UIScrollViewDelegate, 
                                                                          DSMapBoxLayerAddTileViewDelegate,
                                                                          ASIHTTPRequestDelegate>

@property (nonatomic, strong) IBOutlet UILabel *helpLabel;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *spinner;
@property (nonatomic, strong) IBOutlet UIScrollView *tileScrollView;
@property (nonatomic, strong) IBOutlet UIPageControl *tilePageControl;
@property (nonatomic, strong) NSString *serverName;
@property (nonatomic, strong) NSURL *serverURL;

@end
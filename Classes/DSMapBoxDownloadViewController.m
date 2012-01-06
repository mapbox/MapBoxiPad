//
//  DSMapBoxDownloadViewController.m
//  MapBoxiPad
//
//  Created by Justin Miller on 8/16/11.
//  Copyright 2011 Development Seed. All rights reserved.
//

#import "DSMapBoxDownloadViewController.h"

#import "DSMapBoxDownloadManager.h"
#import "DSMapBoxDownloadTableViewCell.h"
#import "DSMapBoxTintedBarButtonItem.h"

#import "SSPieProgressView.h"

@interface DSMapBoxDownloadViewController ()

- (void)reloadTableView;
- (void)downloadProgressUpdated:(NSNotification *)notification;

@end

#pragma mark -

@implementation DSMapBoxDownloadViewController

- (void)viewDidLoad
{
    [self reloadTableView];
    
    self.navigationItem.title = @"Downloads";
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit
                                                                                           target:self
                                                                                           action:@selector(editButtonTapped:)];
    
    // watch for download queue
    //
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(downloadQueueChanged:)
                                                 name:DSMapBoxDownloadQueueNotification
                                               object:nil];
    
    // watch for download progress
    //
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(downloadProgressUpdated:)
                                                 name:DSMapBoxDownloadProgressNotification
                                               object:nil];
    
    // watch for download completion
    //
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(downloadCompleted:)
                                                 name:DSMapBoxDownloadCompleteNotification
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [self reloadTableView];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DSMapBoxDownloadQueueNotification    object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DSMapBoxDownloadProgressNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DSMapBoxDownloadCompleteNotification object:nil];
}

#pragma mark -

- (void)reloadTableView
{
    [self.tableView reloadData];
    
    self.contentSizeForViewInPopover = CGSizeMake(self.contentSizeForViewInPopover.width, 200);
    
    if ([self.tableView numberOfRowsInSection:0])
    {
        self.tableView.editing = NO;
        
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit
                                                                                               target:self
                                                                                               action:@selector(editButtonTapped:)];
    }
    else
    {
        self.navigationItem.rightBarButtonItem = nil;
    }
}

- (void)downloadQueueChanged:(NSNotification *)notification
{
    [self reloadTableView];
}

- (void)downloadProgressUpdated:(NSNotification *)notification
{
    if ( ! [[notification object] isEqual:[DSMapBoxDownloadManager sharedManager]])
    {
        NSURLConnection *download = [notification object];
        
        CGFloat progress = [[[notification userInfo] objectForKey:DSMapBoxDownloadProgressKey] floatValue];
        
        int row = [[DSMapBoxDownloadManager sharedManager].downloads indexOfObject:download];
        
        DSMapBoxDownloadTableViewCell *cell = (DSMapBoxDownloadTableViewCell *)[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
        
        cell.pie.progress = progress;
    }
}

- (void)downloadCompleted:(NSNotification *)notification
{
    [self reloadTableView];
}

#pragma mark -

- (void)editButtonTapped:(id)sender
{
    self.tableView.editing = YES;
    
    self.navigationItem.rightBarButtonItem = [[DSMapBoxTintedBarButtonItem alloc] initWithTitle:@"Done" 
                                                                                         target:self
                                                                                         action:@selector(doneButtonTapped:)];
}

- (void)doneButtonTapped:(id)sender
{
    self.tableView.editing = NO;
    
    if ([self.tableView numberOfRowsInSection:0])
    {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit
                                                                                               target:self
                                                                                               action:@selector(editButtonTapped:)];
    }
    else
    {
        self.navigationItem.rightBarButtonItem = nil;
    }
}

#pragma mark -

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [[DSMapBoxDownloadManager sharedManager].downloads count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    DSMapBoxDownloadManager *manager = [DSMapBoxDownloadManager sharedManager];

    NSURLConnection *download = [manager.downloads objectAtIndex:indexPath.row];
    
    NSArray *nib = [[NSBundle mainBundle] loadNibNamed:@"DSMapBoxDownloadTableViewCell" owner:self options:nil];
    
    DSMapBoxDownloadTableViewCell *cell = (DSMapBoxDownloadTableViewCell *)[nib objectAtIndex:0];
    
    cell.primaryLabel.text   = [download.originalRequest.URL lastPathComponent];
    cell.secondaryLabel.text = [download.originalRequest.URL host];
    
    cell.isPaused = [manager downloadIsPaused:download];
    
    return (UITableViewCell *)cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    DSMapBoxDownloadManager *manager = [DSMapBoxDownloadManager sharedManager];
    
    NSURLConnection *download = [manager.downloads objectAtIndex:indexPath.row];
    
    [manager cancelDownload:download];
    
    [self reloadTableView];
}

#pragma mark -

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return @"Cancel";
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    DSMapBoxDownloadManager *manager = [DSMapBoxDownloadManager sharedManager];
    
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    
    NSURLConnection *download = [manager.downloads objectAtIndex:indexPath.row];

    if (((DSMapBoxDownloadTableViewCell *)[tableView cellForRowAtIndexPath:indexPath]).isPaused)
        [manager resumeDownload:download];

    else
        [manager pauseDownload:download];

    [self reloadTableView];
}

@end
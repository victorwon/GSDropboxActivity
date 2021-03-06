//
//  GSDropboxDestinationSelectionViewController.m
//
//  Created by Simon Whitaker on 06/11/2012.
//  Copyright (c) 2012 Goo Software Ltd. All rights reserved.
//

#import "GSDropboxDestinationSelectionViewController.h"
#import "DropboxSDK.h"

#define kDropboxConnectionMaxRetries 1

@interface GSDropboxDestinationSelectionViewController () <DBRestClientDelegate>
@property (nonatomic) BOOL isLoading;
@property (nonatomic, strong) NSArray *subdirectories;
@property (nonatomic, strong) DBRestClient *dropboxClient;
@property (nonatomic) NSUInteger dropboxConnectionRetryCount;

- (void)handleApplicationBecameActive:(NSNotification *)notification;
- (void)handleCancel;
- (void)handleSelectDestination;

@end

@implementation GSDropboxDestinationSelectionViewController

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        _isLoading = YES;
        self.dropboxConnectionRetryCount = 0;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                           target:self
                                                                                           action:@selector(handleCancel)];
    
    self.toolbarItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
        [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Choose", @"Title for button that user taps to specify the current folder as the storage location for uploads.")
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(handleSelectDestination)]
    ];
    
    [self.navigationController setToolbarHidden:NO];
    self.navigationController.navigationBar.tintColor = [UIColor darkGrayColor];
    self.navigationController.toolbar.tintColor = [UIColor darkGrayColor];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleApplicationBecameActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleApplicationBecameActive:)
                                                 name:@"DropBoxCallback"
                                               object:nil]; // setup handleOpenURL in app delegate to post this notification
/*
 * Sample handleOpenURL code
    - (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
        if ([[DBSession sharedSession] handleOpenURL:url]) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DropBoxCallback" object:nil];
 
            return YES;
        }
        
        // Do something with the url here for other pattern, if any
        return NO;
    }
*/
    
}

- (void)viewDidUnload
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [super viewDidUnload];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (self.navigationController.viewControllers.count == 1 && [[DBSession sharedSession] isLinked]) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Sign out", @"Sharing services logout button")
                                                                                 style:UIBarButtonItemStylePlain
                                                                                target:self
                                                                                action:@selector(handleLogoutConfirm)];
    }

    [self updateChooseButton];
    
    if (self.rootPath == nil)
        self.rootPath = @"/";
    
    if ([self.rootPath isEqualToString:@"/"]) {
        self.title = @"Dropbox";
    } else {
        self.title = [self.rootPath lastPathComponent];
    }
    self.navigationItem.prompt = NSLocalizedString(@"Choose a destination for uploads.", @"Prompt asking user to select a destination folder on Dropbox to which uploads will be saved.") ;
    self.isLoading = YES;
    self.navigationItem.rightBarButtonItem.enabled = YES;
}

- (void) updateChooseButton {
    NSArray* toolbarButtons = self.toolbarItems;
    if(toolbarButtons.count < 2) {
        //Not found
        return;
    }
    UIBarButtonItem *item = toolbarButtons[1];
    BOOL hasValidData = [self hasValidData];
    item.enabled = hasValidData;
}

- (BOOL) hasValidData {
    BOOL valid = self.subdirectories != nil && self.isLoading == NO;
    return valid;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (![[DBSession sharedSession] isLinked]) {
        [self showLoginDialogOrCancel];
    } else {
        [self.dropboxClient loadMetadata:self.rootPath];
    }
}

- (void) showLoginDialogOrCancel {
    if(self.dropboxConnectionRetryCount < kDropboxConnectionMaxRetries) {
        self.dropboxConnectionRetryCount++;
        //disable cancel button, as if the user pressed it while we're presenting
        //the loging viewcontroller (async), UIKit crashes with multiple viewcontroller
        //animations
        self.navigationItem.rightBarButtonItem.enabled = NO;
        [[DBSession sharedSession] linkFromController:self];
    } else {
        self.navigationItem.rightBarButtonItem.enabled = YES;
        [self.delegate dropboxDestinationSelectionViewControllerDidCancel:self];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
        return YES;
    
    return toInterfaceOrientation != UIInterfaceOrientationPortraitUpsideDown;
}

- (DBRestClient *)dropboxClient
{
    if (_dropboxClient == nil && [DBSession sharedSession] != nil) {
        _dropboxClient = [[DBRestClient alloc] initWithSession:[DBSession sharedSession]];
        _dropboxClient.delegate = self;
    }
    return _dropboxClient;
}

#pragma mark - Table view data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (![self hasValidData] || self.subdirectories.count < 1) return 1;

    return [self.subdirectories count];
    
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }
    
    // Configure the cell...
    if (self.isLoading) {
        cell.textLabel.text = NSLocalizedString(@"Loading...", @"Progress message while app is loading a list of folders from Dropbox");
    } else if (self.subdirectories == nil) {
        cell.textLabel.text = NSLocalizedString(@"Error loading folder contents", @"Error message if the app couldn't load a list of a folder's contents from Dropbox");
    } else if ([self.subdirectories count] == 0) {
        if (self.showOnlyDirectories == YES) {
            cell.textLabel.text = NSLocalizedString(@"Contains no folders", @"Status message when the current folder contains no sub-folders");
        } else {
            cell.textLabel.text = NSLocalizedString(@"Contains no folders or files", @"Status message when the current folder contains no sub-folders");
        }
    } else {

        DBMetadata* metadata = [self.subdirectories objectAtIndex:indexPath.row];
        
        cell.textLabel.text = [metadata.filename lastPathComponent];
        
        if (metadata.isDirectory) {
            cell.imageView.image = [UIImage imageNamed:@"OtherFolder"];
            cell.selectionStyle =  UITableViewCellSelectionStyleDefault;
            cell.textLabel.textColor = [UIColor blackColor];
        } else {
            cell.imageView.image = [UIImage imageNamed:@"GenericFile"];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.textColor = [UIColor grayColor];
        }
    }
    
    return cell;
}

#pragma mark - Table view delegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 45.0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if ([cell selectionStyle] == UITableViewCellSelectionStyleNone) {
        return;
    }

    if ([self.subdirectories count] > indexPath.row) {
        GSDropboxDestinationSelectionViewController *vc = [[GSDropboxDestinationSelectionViewController alloc] init];
        vc.delegate = self.delegate;
        vc.rootPath = [self.rootPath stringByAppendingPathComponent:((DBMetadata*)[self.subdirectories objectAtIndex:indexPath.row]).filename];
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
}

#pragma mark - Dropbox client delegate methods

NSInteger dbMetadataSort(DBMetadata* d1, DBMetadata* d2, void *context)
{
    // list directories first
    if (d1.isDirectory && !d2.isDirectory) {
        return -1;
    } else if (!d1.isDirectory && d2.isDirectory) {
        return 1;
    }
    return [d1.filename compare:d2.filename];
}

- (void)restClient:(DBRestClient *)client loadedMetadata:(DBMetadata *)metadata
{
    NSMutableArray *array = [NSMutableArray array];
    for (DBMetadata *file in metadata.contents) {
        if ([file.filename length] > 0 && [file.filename characterAtIndex:0] != '.') {
            if (self.showOnlyDirectories == NO || (self.showOnlyDirectories == YES && file.isDirectory)) {
                [array addObject:file];
            }
        }
    }

    self.subdirectories = [array sortedArrayUsingFunction:dbMetadataSort context:NULL];
    
    self.isLoading = NO;
    [self updateChooseButton];
    
    self.navigationItem.rightBarButtonItem.enabled = YES;

}

- (void)restClient:(DBRestClient *)client loadMetadataFailedWithError:(NSError *)error
{
    // Error 401 gets returned if a token is invalid, e.g. if the user has deleted
    // the app from their list of authorized apps at dropbox.com
    if (error.code == 401) {
        [self showLoginDialogOrCancel];
    } else if (error.code == 403) {
        // user canceled dropbox.com authentication
        [self handleCancel];
    } else {
        self.isLoading = NO;
    }
    [self updateChooseButton];
    
    self.navigationItem.rightBarButtonItem.enabled = YES;

}

- (void)setIsLoading:(BOOL)isLoading
{
    if (_isLoading != isLoading) {
        _isLoading = isLoading;
        [self.tableView reloadData];
    }
}

- (void)handleLogoutConfirm
{
    UIAlertView* alert = [[UIAlertView alloc] initWithTitle:@"Sign out of Dropbox?"
                                                    message:nil
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Sign out", nil];
    [alert show];
}

- (void)handleLogout
{
    [[DBSession sharedSession] unlinkAll];
    
    self.dropboxConnectionRetryCount = 0;
    [self showLoginDialogOrCancel];
    
}

- (void)handleCancel
{
    id<GSDropboxDestinationSelectionViewControllerDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(dropboxDestinationSelectionViewControllerDidCancel:)]) {
        [delegate dropboxDestinationSelectionViewControllerDidCancel:self];
    }
}

- (void)handleSelectDestination
{
    id<GSDropboxDestinationSelectionViewControllerDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(dropboxDestinationSelectionViewController:didSelectDestinationPath:)]) {
        [delegate dropboxDestinationSelectionViewController:self
                                   didSelectDestinationPath:self.rootPath];
    }
}

- (void)handleApplicationBecameActive:(NSNotification *)notification
{
    // Happens after user has been bounced out to Dropbox.app or Safari.app
    // to authenticate
    if ([[DBSession sharedSession] isLinked] == YES) {
        [self.dropboxClient loadMetadata:self.rootPath];
        self.isLoading = YES;
        self.navigationItem.rightBarButtonItem.enabled = YES;
    } else {
        [self performSelector:@selector(handleCancel) withObject:nil afterDelay:1.0f]; // delay at least 1s to avoid conflict when user taps cancel button during DB login.
    }
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 1) {
        [self handleLogout];
    }
}

@end

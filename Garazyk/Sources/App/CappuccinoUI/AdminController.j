/*
 * AdminController.j
 * CappuccinoUI
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>
@import "SessionState.j"
@import "UIAPIClient.j"
@import "EmptyStateView.j"

@implementation AdminController : CPObject
{
    SessionState _sessionState;
    UIAPIClient _apiClient;
    CPView _rootView;

    CPTextField _statusLabel;
    CPTextField _passwordField;
    CPTextField _authStateLabel;
    CPTabView _tabView;

    CPTextView _overviewTextView;

    CPTextField _accountsSearchField;
    CPTableView _accountsTable;
    CPTextView _accountsDetailTextView;
    CPTextView _accountsResultTextView;

    CPPopUpButton _reportsStatusFilterPopup;
    CPTextField _reportsReasonFilterField;
    CPTextField _reportsSubjectFilterField;
    CPTableView _reportsTable;
    CPTextView _reportsDetailTextView;
    CPTextField _reportsNotesField;
    CPTextView _reportsResultTextView;

    CPTextView _systemStatusTextView;
    CPTextView _auditPreviewTextView;

    CPTextField _inviteForAccountField;
    CPTextField _inviteUsesField;
    CPTableView _invitesTable;
    CPTextView _invitesResultTextView;

    CPTableView _moderationTable;
    CPTextView _moderationResultTextView;

    CPWindow _auditModalWindow;
    CPPopUpButton _auditFilterPopup;
    CPTextView _auditModalTextView;

    CPArray _accounts;
    CPArray _filteredAccounts;
    CPArray _reports;
    CPArray _invites;
    CPArray _moderationUsers;
    CPArray _auditEntries;
    CPString _adminToken;
}

- (id)initWithSessionState:(SessionState)sessionState apiClient:(UIAPIClient)apiClient
{
    self = [super init];
    if (self)
    {
        _sessionState = sessionState;
        _apiClient = apiClient;
        _accounts = [];
        _filteredAccounts = [];
        _reports = [];
        _invites = [];
        _moderationUsers = [];
        _auditEntries = [];
        _adminToken = nil;
    }
    return self;
}

- (CPView)rootView
{
    if (_rootView)
        return _rootView;

    _rootView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1080.0, 700.0)];

    var title = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 16.0, 900.0, 28.0)];
    [title setStringValue:@"Admin"];
    [title setEditable:NO];
    [title setBezeled:NO];
    [title setDrawsBackground:NO];
    [title setFont:[CPFont boldSystemFontOfSize:20.0]];

    _statusLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 44.0, 1038.0, 20.0)];
    [_statusLabel setEditable:NO];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setFont:[CPFont systemFontOfSize:12.0]];
    [_statusLabel setStringValue:@"Idle"];

    var passwordLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 72.0, 62.0, 18.0)];
    [passwordLabel setStringValue:@"Password:"];
    [passwordLabel setEditable:NO];
    [passwordLabel setBezeled:NO];
    [passwordLabel setDrawsBackground:NO];

    _passwordField = [[CPTextField alloc] initWithFrame:CGRectMake(86.0, 68.0, 210.0, 26.0)];
    [_passwordField setPlaceholderString:@"Admin password"];
    // Accessibility:
    // Accessibility:

    var loginButton = [[CPButton alloc] initWithFrame:CGRectMake(304.0, 68.0, 72.0, 28.0)];
    [loginButton setTitle:@"Login"];
    [loginButton setTarget:self];
    [loginButton setAction:@selector(handleLogin:)];

    var logoutButton = [[CPButton alloc] initWithFrame:CGRectMake(382.0, 68.0, 78.0, 28.0)];
    [logoutButton setTitle:@"Logout"];
    [logoutButton setTarget:self];
    [logoutButton setAction:@selector(handleLogout:)];

    _authStateLabel = [[CPTextField alloc] initWithFrame:CGRectMake(470.0, 72.0, 170.0, 18.0)];
    [_authStateLabel setEditable:NO];
    [_authStateLabel setBezeled:NO];
    [_authStateLabel setDrawsBackground:NO];
    [_authStateLabel setStringValue:@"Auth: Signed out"];

    var openOverviewButton = [[CPButton alloc] initWithFrame:CGRectMake(660.0, 68.0, 114.0, 28.0)];
    [openOverviewButton setTitle:@"Open Overview"];
    [openOverviewButton setTarget:self];
    [openOverviewButton setAction:@selector(handleOpenOverviewPanel:)];

    var openInvitesButton = [[CPButton alloc] initWithFrame:CGRectMake(782.0, 68.0, 106.0, 28.0)];
    [openInvitesButton setTitle:@"Invite Codes"];
    [openInvitesButton setTarget:self];
    [openInvitesButton setAction:@selector(handleOpenInvitesPanel:)];

    var openModerationButton = [[CPButton alloc] initWithFrame:CGRectMake(896.0, 68.0, 132.0, 28.0)];
    [openModerationButton setTitle:@"Moderation"];
    [openModerationButton setTarget:self];
    [openModerationButton setAction:@selector(handleOpenModerationPanel:)];

    _tabView = [[CPTabView alloc] initWithFrame:CGRectMake(20.0, 104.0, 1040.0, 576.0)];
    [_tabView setDelegate:self];
    [self setUpAdminTabs];

    [_rootView addSubview:title];
    [_rootView addSubview:_statusLabel];
    [_rootView addSubview:passwordLabel];
    [_rootView addSubview:_passwordField];
    [_rootView addSubview:loginButton];
    [_rootView addSubview:logoutButton];
    [_rootView addSubview:_authStateLabel];
    [_rootView addSubview:openOverviewButton];
    [_rootView addSubview:openInvitesButton];
    [_rootView addSubview:openModerationButton];
    [_rootView addSubview:_tabView];

    [self restoreAdminSessionFromStorage];
    [self selectTabWithIdentifier:@"overview"];
    if (_adminToken)
        [self loadOverviewStats];

    return _rootView;
}

- (void)setUpAdminTabs
{
    var overviewTab = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1020.0, 530.0)];
    var refreshOverviewButton = [[CPButton alloc] initWithFrame:CGRectMake(10.0, 8.0, 140.0, 28.0)];
    [refreshOverviewButton setTitle:@"Refresh Overview"];
    [refreshOverviewButton setTarget:self];
    [refreshOverviewButton setAction:@selector(handleRefreshOverview:)];
    [overviewTab addSubview:refreshOverviewButton];
    _overviewTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(10.0, 44.0, 1000.0, 472.0)
                                                       inView:overviewTab];
    [self addTabItemWithIdentifier:@"overview" label:@"Overview" contentView:overviewTab];

    var accountsTab = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1020.0, 530.0)];
    var accountsSearchLabel = [[CPTextField alloc] initWithFrame:CGRectMake(10.0, 12.0, 52.0, 18.0)];
    [accountsSearchLabel setStringValue:@"Search:"];
    [accountsSearchLabel setEditable:NO];
    [accountsSearchLabel setBezeled:NO];
    [accountsSearchLabel setDrawsBackground:NO];
    [accountsTab addSubview:accountsSearchLabel];

    _accountsSearchField = [[CPTextField alloc] initWithFrame:CGRectMake(66.0, 8.0, 230.0, 24.0)];
    [_accountsSearchField setPlaceholderString:@"handle, DID, email"];
    [accountsTab addSubview:_accountsSearchField];

    var accountsSearchButton = [[CPButton alloc] initWithFrame:CGRectMake(304.0, 6.0, 70.0, 28.0)];
    [accountsSearchButton setTitle:@"Search"];
    [accountsSearchButton setTarget:self];
    [accountsSearchButton setAction:@selector(handleSearchAccounts:)];
    [accountsTab addSubview:accountsSearchButton];

    var accountsClearButton = [[CPButton alloc] initWithFrame:CGRectMake(380.0, 6.0, 60.0, 28.0)];
    [accountsClearButton setTitle:@"Clear"];
    [accountsClearButton setTarget:self];
    [accountsClearButton setAction:@selector(handleClearAccountSearch:)];
    [accountsTab addSubview:accountsClearButton];

    var accountsRefreshButton = [[CPButton alloc] initWithFrame:CGRectMake(448.0, 6.0, 114.0, 28.0)];
    [accountsRefreshButton setTitle:@"Reload Accounts"];
    [accountsRefreshButton setTarget:self];
    [accountsRefreshButton setAction:@selector(handleRefreshAccounts:)];
    [accountsTab addSubview:accountsRefreshButton];

    _accountsTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 390.0, 480.0)];
    [_accountsTable setDelegate:self];
    [_accountsTable setDataSource:self];
    [_accountsTable setAllowsEmptySelection:YES];
    [_accountsTable setAllowsMultipleSelection:NO];

    var accountsHandleColumn = [[CPTableColumn alloc] initWithIdentifier:@"account_handle"];
    [[accountsHandleColumn headerView] setStringValue:@"Handle"];
    [accountsHandleColumn setWidth:160.0];
    [_accountsTable addTableColumn:accountsHandleColumn];

    var accountsDidColumn = [[CPTableColumn alloc] initWithIdentifier:@"account_did"];
    [[accountsDidColumn headerView] setStringValue:@"DID"];
    [accountsDidColumn setWidth:220.0];
    [_accountsTable addTableColumn:accountsDidColumn];

    var accountsScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(10.0, 40.0, 390.0, 480.0)];
    [accountsScroll setHasVerticalScroller:YES];
    [accountsScroll setAutohidesScrollers:YES];
    [accountsScroll setDocumentView:_accountsTable];
    [accountsTab addSubview:accountsScroll];

    _accountsDetailTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(410.0, 40.0, 600.0, 330.0)
                                                             inView:accountsTab];

    var accountDisableButton = [[CPButton alloc] initWithFrame:CGRectMake(410.0, 380.0, 140.0, 28.0)];
    [accountDisableButton setTitle:@"Disable Invites"];
    [accountDisableButton setTarget:self];
    [accountDisableButton setAction:@selector(handleDisableSelectedAccountInvites:)];
    [accountsTab addSubview:accountDisableButton];

    var accountEnableButton = [[CPButton alloc] initWithFrame:CGRectMake(558.0, 380.0, 132.0, 28.0)];
    [accountEnableButton setTitle:@"Enable Invites"];
    [accountEnableButton setTarget:self];
    [accountEnableButton setAction:@selector(handleEnableSelectedAccountInvites:)];
    [accountsTab addSubview:accountEnableButton];

    var accountInfoButton = [[CPButton alloc] initWithFrame:CGRectMake(698.0, 380.0, 96.0, 28.0)];
    [accountInfoButton setTitle:@"Get Info..."];
    [accountInfoButton setTarget:self];
    [accountInfoButton setAction:@selector(handleShowSelectedAccountInfo:)];
    [accountsTab addSubview:accountInfoButton];

    _accountsResultTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(410.0, 418.0, 600.0, 102.0)
                                                             inView:accountsTab];
    [self addTabItemWithIdentifier:@"accounts" label:@"Accounts" contentView:accountsTab];

    var reportsTab = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1020.0, 530.0)];
    var reportsStatusLabel = [[CPTextField alloc] initWithFrame:CGRectMake(10.0, 12.0, 46.0, 18.0)];
    [reportsStatusLabel setStringValue:@"Status:"];
    [reportsStatusLabel setEditable:NO];
    [reportsStatusLabel setBezeled:NO];
    [reportsStatusLabel setDrawsBackground:NO];
    [reportsTab addSubview:reportsStatusLabel];

    _reportsStatusFilterPopup = [[CPPopUpButton alloc] initWithFrame:CGRectMake(58.0, 10.0, 120.0, 24.0)];
    [_reportsStatusFilterPopup addItemsWithTitles:[@"all,open,in_progress,resolved,dismissed" componentsSeparatedByString:@","]];
    [reportsTab addSubview:_reportsStatusFilterPopup];

    var reportsReasonLabel = [[CPTextField alloc] initWithFrame:CGRectMake(188.0, 12.0, 48.0, 18.0)];
    [reportsReasonLabel setStringValue:@"Reason:"];
    [reportsReasonLabel setEditable:NO];
    [reportsReasonLabel setBezeled:NO];
    [reportsReasonLabel setDrawsBackground:NO];
    [reportsTab addSubview:reportsReasonLabel];

    _reportsReasonFilterField = [[CPTextField alloc] initWithFrame:CGRectMake(238.0, 10.0, 220.0, 24.0)];
    [_reportsReasonFilterField setPlaceholderString:@"reasonType (optional)"];
    [reportsTab addSubview:_reportsReasonFilterField];

    var reportsSubjectLabel = [[CPTextField alloc] initWithFrame:CGRectMake(466.0, 12.0, 56.0, 18.0)];
    [reportsSubjectLabel setStringValue:@"Subject:"];
    [reportsSubjectLabel setEditable:NO];
    [reportsSubjectLabel setBezeled:NO];
    [reportsSubjectLabel setDrawsBackground:NO];
    [reportsTab addSubview:reportsSubjectLabel];

    _reportsSubjectFilterField = [[CPTextField alloc] initWithFrame:CGRectMake(524.0, 10.0, 230.0, 24.0)];
    [_reportsSubjectFilterField setPlaceholderString:@"subject DID (optional)"];
    [reportsTab addSubview:_reportsSubjectFilterField];

    var reportsLoadButton = [[CPButton alloc] initWithFrame:CGRectMake(764.0, 8.0, 86.0, 28.0)];
    [reportsLoadButton setTitle:@"Load"];
    [reportsLoadButton setTarget:self];
    [reportsLoadButton setAction:@selector(handleLoadReports:)];
    [reportsTab addSubview:reportsLoadButton];

    _reportsTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 430.0, 480.0)];
    [_reportsTable setDelegate:self];
    [_reportsTable setDataSource:self];
    [_reportsTable setAllowsEmptySelection:YES];
    [_reportsTable setAllowsMultipleSelection:NO];

    var reportsStatusColumn = [[CPTableColumn alloc] initWithIdentifier:@"report_status"];
    [[reportsStatusColumn headerView] setStringValue:@"Status"];
    [reportsStatusColumn setWidth:75.0];
    [_reportsTable addTableColumn:reportsStatusColumn];

    var reportsReasonColumn = [[CPTableColumn alloc] initWithIdentifier:@"report_reason"];
    [[reportsReasonColumn headerView] setStringValue:@"Reason"];
    [reportsReasonColumn setWidth:170.0];
    [_reportsTable addTableColumn:reportsReasonColumn];

    var reportsSubjectColumn = [[CPTableColumn alloc] initWithIdentifier:@"report_subject"];
    [[reportsSubjectColumn headerView] setStringValue:@"Subject"];
    [reportsSubjectColumn setWidth:175.0];
    [_reportsTable addTableColumn:reportsSubjectColumn];

    var reportsScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(10.0, 40.0, 430.0, 480.0)];
    [reportsScroll setHasVerticalScroller:YES];
    [reportsScroll setAutohidesScrollers:YES];
    [reportsScroll setDocumentView:_reportsTable];
    [reportsTab addSubview:reportsScroll];

    _reportsDetailTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(448.0, 40.0, 562.0, 318.0)
                                                            inView:reportsTab];

    var notesLabel = [[CPTextField alloc] initWithFrame:CGRectMake(448.0, 366.0, 44.0, 18.0)];
    [notesLabel setStringValue:@"Notes:"];
    [notesLabel setEditable:NO];
    [notesLabel setBezeled:NO];
    [notesLabel setDrawsBackground:NO];
    [reportsTab addSubview:notesLabel];

    _reportsNotesField = [[CPTextField alloc] initWithFrame:CGRectMake(492.0, 362.0, 320.0, 24.0)];
    [_reportsNotesField setPlaceholderString:@"resolution notes (optional)"];
    [reportsTab addSubview:_reportsNotesField];

    var dismissReportButton = [[CPButton alloc] initWithFrame:CGRectMake(820.0, 360.0, 90.0, 28.0)];
    [dismissReportButton setTitle:@"Dismiss"];
    [dismissReportButton setTarget:self];
    [dismissReportButton setAction:@selector(handleDismissSelectedReport:)];
    [reportsTab addSubview:dismissReportButton];

    var resolveReportButton = [[CPButton alloc] initWithFrame:CGRectMake(918.0, 360.0, 90.0, 28.0)];
    [resolveReportButton setTitle:@"Resolve"];
    [resolveReportButton setTarget:self];
    [resolveReportButton setAction:@selector(handleResolveSelectedReport:)];
    [reportsTab addSubview:resolveReportButton];

    _reportsResultTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(448.0, 396.0, 562.0, 124.0)
                                                            inView:reportsTab];
    [self addTabItemWithIdentifier:@"reports" label:@"Reports" contentView:reportsTab];

    var systemTab = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1020.0, 530.0)];
    var refreshSystemButton = [[CPButton alloc] initWithFrame:CGRectMake(10.0, 8.0, 126.0, 28.0)];
    [refreshSystemButton setTitle:@"Refresh System"];
    [refreshSystemButton setTarget:self];
    [refreshSystemButton setAction:@selector(handleRefreshSystem:)];
    [systemTab addSubview:refreshSystemButton];

    var viewAuditButton = [[CPButton alloc] initWithFrame:CGRectMake(144.0, 8.0, 122.0, 28.0)];
    [viewAuditButton setTitle:@"View Full Audit"];
    [viewAuditButton setTarget:self];
    [viewAuditButton setAction:@selector(handleOpenFullAuditLog:)];
    [systemTab addSubview:viewAuditButton];

    var manageInvitesButton = [[CPButton alloc] initWithFrame:CGRectMake(274.0, 8.0, 160.0, 28.0)];
    [manageInvitesButton setTitle:@"Manage Invite Codes..."];
    [manageInvitesButton setTarget:self];
    [manageInvitesButton setAction:@selector(handleManageInvitesFromSystem:)];
    [systemTab addSubview:manageInvitesButton];

    _systemStatusTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(10.0, 44.0, 1000.0, 200.0)
                                                           inView:systemTab];
    _auditPreviewTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(10.0, 252.0, 1000.0, 264.0)
                                                           inView:systemTab];
    [self addTabItemWithIdentifier:@"system" label:@"System" contentView:systemTab];

    var invitesTab = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1020.0, 530.0)];
    var inviteForLabel = [[CPTextField alloc] initWithFrame:CGRectMake(10.0, 12.0, 72.0, 18.0)];
    [inviteForLabel setStringValue:@"forAccount:"];
    [inviteForLabel setEditable:NO];
    [inviteForLabel setBezeled:NO];
    [inviteForLabel setDrawsBackground:NO];
    [invitesTab addSubview:inviteForLabel];

    _inviteForAccountField = [[CPTextField alloc] initWithFrame:CGRectMake(84.0, 10.0, 220.0, 24.0)];
    [_inviteForAccountField setPlaceholderString:@"did:plc:... (optional)"];
    [invitesTab addSubview:_inviteForAccountField];

    var inviteUsesLabel = [[CPTextField alloc] initWithFrame:CGRectMake(314.0, 12.0, 34.0, 18.0)];
    [inviteUsesLabel setStringValue:@"Uses:"];
    [inviteUsesLabel setEditable:NO];
    [inviteUsesLabel setBezeled:NO];
    [inviteUsesLabel setDrawsBackground:NO];
    [invitesTab addSubview:inviteUsesLabel];

    _inviteUsesField = [[CPTextField alloc] initWithFrame:CGRectMake(350.0, 10.0, 50.0, 24.0)];
    [_inviteUsesField setStringValue:@"1"];
    [invitesTab addSubview:_inviteUsesField];

    var invitesLoadButton = [[CPButton alloc] initWithFrame:CGRectMake(408.0, 8.0, 64.0, 28.0)];
    [invitesLoadButton setTitle:@"Load"];
    [invitesLoadButton setTarget:self];
    [invitesLoadButton setAction:@selector(handleLoadInvites:)];
    [invitesTab addSubview:invitesLoadButton];

    var invitesGenerateButton = [[CPButton alloc] initWithFrame:CGRectMake(478.0, 8.0, 86.0, 28.0)];
    [invitesGenerateButton setTitle:@"Generate"];
    [invitesGenerateButton setTarget:self];
    [invitesGenerateButton setAction:@selector(handleGenerateInviteCode:)];
    [invitesTab addSubview:invitesGenerateButton];

    var invitesDisableButton = [[CPButton alloc] initWithFrame:CGRectMake(570.0, 8.0, 124.0, 28.0)];
    [invitesDisableButton setTitle:@"Disable Selected"];
    [invitesDisableButton setTarget:self];
    [invitesDisableButton setAction:@selector(handleDisableSelectedInvite:)];
    [invitesTab addSubview:invitesDisableButton];

    _invitesTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1000.0, 340.0)];
    [_invitesTable setDelegate:self];
    [_invitesTable setDataSource:self];
    [_invitesTable setAllowsEmptySelection:YES];
    [_invitesTable setAllowsMultipleSelection:NO];

    var inviteCodeColumn = [[CPTableColumn alloc] initWithIdentifier:@"invite_code"];
    [[inviteCodeColumn headerView] setStringValue:@"Code"];
    [inviteCodeColumn setWidth:290.0];
    [_invitesTable addTableColumn:inviteCodeColumn];

    var inviteCreatedByColumn = [[CPTableColumn alloc] initWithIdentifier:@"invite_created_by"];
    [[inviteCreatedByColumn headerView] setStringValue:@"Created By"];
    [inviteCreatedByColumn setWidth:270.0];
    [_invitesTable addTableColumn:inviteCreatedByColumn];

    var inviteUsesColumn = [[CPTableColumn alloc] initWithIdentifier:@"invite_uses"];
    [[inviteUsesColumn headerView] setStringValue:@"Uses"];
    [inviteUsesColumn setWidth:120.0];
    [_invitesTable addTableColumn:inviteUsesColumn];

    var inviteStatusColumn = [[CPTableColumn alloc] initWithIdentifier:@"invite_status"];
    [[inviteStatusColumn headerView] setStringValue:@"Status"];
    [inviteStatusColumn setWidth:120.0];
    [_invitesTable addTableColumn:inviteStatusColumn];

    var inviteCreatedAtColumn = [[CPTableColumn alloc] initWithIdentifier:@"invite_created_at"];
    [[inviteCreatedAtColumn headerView] setStringValue:@"Created At"];
    [inviteCreatedAtColumn setWidth:190.0];
    [_invitesTable addTableColumn:inviteCreatedAtColumn];

    var invitesScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(10.0, 40.0, 1000.0, 340.0)];
    [invitesScroll setHasVerticalScroller:YES];
    [invitesScroll setAutohidesScrollers:YES];
    [invitesScroll setDocumentView:_invitesTable];
    [invitesTab addSubview:invitesScroll];

    _invitesResultTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(10.0, 388.0, 1000.0, 128.0)
                                                            inView:invitesTab];
    [self addTabItemWithIdentifier:@"invites" label:@"Invite Codes" contentView:invitesTab];

    var moderationTab = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1020.0, 530.0)];
    var moderationLoadButton = [[CPButton alloc] initWithFrame:CGRectMake(10.0, 8.0, 104.0, 28.0)];
    [moderationLoadButton setTitle:@"Load Accounts"];
    [moderationLoadButton setTarget:self];
    [moderationLoadButton setAction:@selector(handleLoadModeration:)];
    [moderationTab addSubview:moderationLoadButton];

    var moderationDisableButton = [[CPButton alloc] initWithFrame:CGRectMake(120.0, 8.0, 130.0, 28.0)];
    [moderationDisableButton setTitle:@"Disable Invites"];
    [moderationDisableButton setTarget:self];
    [moderationDisableButton setAction:@selector(handleDisableSelectedModerationAccount:)];
    [moderationTab addSubview:moderationDisableButton];

    var moderationEnableButton = [[CPButton alloc] initWithFrame:CGRectMake(256.0, 8.0, 124.0, 28.0)];
    [moderationEnableButton setTitle:@"Enable Invites"];
    [moderationEnableButton setTarget:self];
    [moderationEnableButton setAction:@selector(handleEnableSelectedModerationAccount:)];
    [moderationTab addSubview:moderationEnableButton];

    _moderationTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1000.0, 340.0)];
    [_moderationTable setDelegate:self];
    [_moderationTable setDataSource:self];
    [_moderationTable setAllowsEmptySelection:YES];
    [_moderationTable setAllowsMultipleSelection:NO];

    var moderationHandleColumn = [[CPTableColumn alloc] initWithIdentifier:@"moderation_handle"];
    [[moderationHandleColumn headerView] setStringValue:@"Handle"];
    [moderationHandleColumn setWidth:240.0];
    [_moderationTable addTableColumn:moderationHandleColumn];

    var moderationDidColumn = [[CPTableColumn alloc] initWithIdentifier:@"moderation_did"];
    [[moderationDidColumn headerView] setStringValue:@"DID"];
    [moderationDidColumn setWidth:520.0];
    [_moderationTable addTableColumn:moderationDidColumn];

    var moderationStatusColumn = [[CPTableColumn alloc] initWithIdentifier:@"moderation_status"];
    [[moderationStatusColumn headerView] setStringValue:@"Status"];
    [moderationStatusColumn setWidth:220.0];
    [_moderationTable addTableColumn:moderationStatusColumn];

    var moderationScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(10.0, 40.0, 1000.0, 340.0)];
    [moderationScroll setHasVerticalScroller:YES];
    [moderationScroll setAutohidesScrollers:YES];
    [moderationScroll setDocumentView:_moderationTable];
    [moderationTab addSubview:moderationScroll];

    _moderationResultTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(10.0, 388.0, 1000.0, 128.0)
                                                               inView:moderationTab];
    [self addTabItemWithIdentifier:@"moderation" label:@"Moderation (Legacy)" contentView:moderationTab];
}

- (void)addTabItemWithIdentifier:(CPString)identifier label:(CPString)label contentView:(CPView)contentView
{
    var item = [[CPTabViewItem alloc] initWithIdentifier:identifier];
    [item setLabel:label];
    [item setView:contentView];
    [_tabView addTabViewItem:item];
}

- (void)selectTabWithIdentifier:(CPString)identifier
{
    if (!identifier)
        return;

    var items = [_tabView tabViewItems] || [],
        i = 0;
    for (i = 0; i < [items count]; i++)
    {
        var item = [items objectAtIndex:i];
        if ([[item identifier] isEqual:identifier])
        {
            [_tabView selectTabViewItem:item];
            return;
        }
    }
}

- (CPTextView)buildReadOnlyTextViewWithFrame:(CGRect)frame inView:(CPView)parent
{
    var textView = [[CPTextView alloc] initWithFrame:CGRectMake(0.0, 0.0, frame.size.width, frame.size.height)];
    [textView setEditable:NO];
    [textView setSelectable:YES];
    [textView setString:@""];
    [textView setFont:[CPFont systemFontOfSize:12.0]];

    var scroll = [[CPScrollView alloc] initWithFrame:frame];
    [scroll setHasVerticalScroller:YES];
    [scroll setAutohidesScrollers:YES];
    [scroll setDocumentView:textView];
    [parent addSubview:scroll];

    return textView;
}

- (void)setStatus:(CPString)message
{
    [_statusLabel setStringValue:(message || @"")];
    [_statusLabel setTextColor:[CPColor colorWithCalibratedWhite:(75.0/255.0) alpha:1.0]];
}

- (void)setErrorStatus:(CPString)message
{
    [_statusLabel setStringValue:@"Error: " + message];
    [_statusLabel setTextColor:[CPColor colorWithCalibratedRed:(185.0/255.0)
                                                         green:(28.0/255.0)
                                                          blue:(28.0/255.0)
                                                         alpha:1.0]];
}

- (void)setSuccessStatus:(CPString)message
{
    [_statusLabel setStringValue:message];
    [_statusLabel setTextColor:[CPColor colorWithCalibratedRed:(4.0/255.0)
                                                         green:(120.0/255.0)
                                                          blue:(87.0/255.0)
                                                         alpha:1.0]];
}

- (void)setWarningStatus:(CPString)message
{
    [_statusLabel setStringValue:@"Warning: " + message];
    [_statusLabel setTextColor:[CPColor colorWithCalibratedRed:(180.0/255.0)
                                                         green:(83.0/255.0)
                                                          blue:(9.0/255.0)
                                                         alpha:1.0]];
}

// Empty state handling for tables
- (void)showEmptyStateInTableView:(CPTableView)tableView
                          withIcon:(CPString)iconName
                          message:(CPString)message
{
    var superview = [tableView superview];
    if (!superview)
        return;

    // Remove any existing empty state
    var subviews = [superview subviews];
    for (var i = 0; i < subviews.length; i++)
    {
        if ([subviews[i] isKindOfClass:[EmptyStateView class]])
            [subviews[i] removeFromSuperview];
    }

    // Show new empty state
    [EmptyStateView emptyStateWithIcon:iconName
                               message:message
                               inView:superview];
}

- (void)hideEmptyStateFromTableView:(CPTableView)tableView
{
    var superview = [tableView superview];
    if (!superview)
        return;

    var subviews = [superview subviews];
    for (var i = 0; i < subviews.length; i++)
    {
        if ([subviews[i] isKindOfClass:[EmptyStateView class]])
            [subviews[i] removeFromSuperview];
    }
}

#pragma mark - Confirmation Dialogs

- (void)confirmDestructiveWithTitle:(CPString)title
                      informativeText:(CPString)text
                        confirmHandler:(Function)handler
{
    var alert = [[CPAlert alloc] init];
    [alert setAlertStyle:CPWarningAlertStyle];
    [alert setMessageText:title];
    [alert setInformativeText:text];

    // Cancel first (index 0), Confirm second (index 1) - standard macOS pattern
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Confirm"];

    // Accessibility
    var buttons = [alert buttons];
    if (buttons && buttons.length >= 2)
    {

    }

    var window = [_rootView window];
    if (window)
    {
        [alert beginSheetModalForWindow:window completionHandler:function(response)
        {
            // response: 0 = Cancel, 1 = Confirm
            if (response === 1 && handler)
                handler();
        }];
    }
    else
    {
        // Fallback if no window - just run handler
        [alert runModal];
        var response = [alert returnValue];
        if (response === 1 && handler)
            handler();
    }
}

- (void)confirmCriticalWithTitle:(CPString)title
                  informativeText:(CPString)text
                  confirmHandler:(Function)handler
{
    var alert = [[CPAlert alloc] init];
    [alert setAlertStyle:CPCriticalAlertStyle];
    [alert setMessageText:title];
    [alert setInformativeText:text];

    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Delete"];

    var buttons = [alert buttons];
    if (buttons && buttons.length >= 2)
    {

    }

    var window = [_rootView window];
    if (window)
    {
        [alert beginSheetModalForWindow:window completionHandler:function(response)
        {
            if (response === 1 && handler)
                handler();
        }];
    }
}

#pragma mark - Guarded Writes Pattern

- (void)guardedWriteWithTitle:(CPString)title
                   action:(CPString)action
                    did:(CPString)did
           preflightSummary:(CPString)summary
               riskLevel:(CPString)riskLevel
          confirmReason:(CPString)reason
            completion:(Function)completion
{
    var riskLabel = @"LOW";
    var alertStyle = CPWarningAlertStyle;
    if ([riskLevel isEqual:@"high"])
    {
        riskLabel = @"HIGH";
        alertStyle = CPCriticalAlertStyle;
    }

    var confirmTitle = @"Confirm " + action;
    var confirmText = "Risk: " + riskLabel + "\n\n" + summary;
    if (reason && reason.length > 0)
    {
        confirmText += "\n\nReason: " + reason;
    }

    var alert = [[CPAlert alloc] init];
    [alert setAlertStyle:alertStyle];
    [alert setMessageText:confirmTitle];
    [alert setInformativeText:confirmText];

    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Confirm"];

    var window = [_rootView window];
    if (window)
    {
        [alert beginSheetModalForWindow:window completionHandler:function(response)
        {
            if (response === 1 && completion)
                completion();
        }];
    }
}

- (void)showExecutionReceipt:(CPString)action
                    did:(CPString)did
               success:(BOOL)success
               auditId:(CPString)auditId
               errorMessage:(CPString)errorMessage
{
    var message = "";
    if (success)
    {
        message = "Action completed: " + action + "\n";
        message += "Target: " + did + "\n";
        if (auditId && auditId.length > 0)
        {
            message += "Audit ID: " + auditId + "\n";
        }
    }
    else
    {
        message = "Action failed: " + action + "\n";
        message += "Error: " + (errorMessage || "Unknown error");
    }

    if (success)
    {
        [self setSuccessStatus:message];
    }
    else
    {
        [self setErrorStatus:message];
    }
}

- (void)setTextView:(CPTextView)textView content:(CPString)content
{
    if (!textView)
        return;

    [textView setString:(content || @"")];
}

- (CPString)trimmedString:(CPString)value
{
    if (!value)
        return @"";

    return String(value).replace(/^\s+|\s+$/g, "");
}

- (CPString)safeString:(id)value
{
    if (value === nil || value === undefined)
        return @"";

    if (typeof value === "string")
        return value;

    return String(value);
}

- (CPString)abbreviatedString:(id)value maxLength:(int)maxLength
{
    var stringValue = [self safeString:value];
    if (!stringValue || stringValue.length <= maxLength)
        return stringValue;
    return stringValue.substring(0, maxLength - 3) + "...";
}

- (CPString)prettyJSON:(id)object
{
    if (object === nil || object === undefined)
        return @"";

    try
    {
        return JSON.stringify(object, null, 2);
    }
    catch (e)
    {
        return String(object);
    }
}

- (CPString)adminStorageKeyToken
{
    return @"admin_token";
}

- (void)setSessionStorageValue:(CPString)value forKey:(CPString)key
{
    if (!key)
        return;

    try
    {
        if (value === nil || value === undefined)
            sessionStorage.removeItem(String(key));
        else
            sessionStorage.setItem(String(key), String(value));
    }
    catch (e)
    {
    }
}

- (CPString)sessionStorageValueForKey:(CPString)key
{
    if (!key)
        return nil;

    try
    {
        return sessionStorage.getItem(String(key));
    }
    catch (e)
    {
    }

    return nil;
}

- (void)syncAuthStateUI
{
    var isAuthenticated = (_adminToken && _adminToken.length > 0);
    [_sessionState setAdminAuthenticated:isAuthenticated];
    [_authStateLabel setStringValue:(isAuthenticated ? @"Auth: Signed in" : @"Auth: Signed out")];
}

- (void)setAdminToken:(CPString)token
{
    _adminToken = token;
    [self setSessionStorageValue:token forKey:[self adminStorageKeyToken]];
    [self syncAuthStateUI];
}

- (void)clearAdminToken
{
    _adminToken = nil;
    [self setSessionStorageValue:nil forKey:[self adminStorageKeyToken]];
    [self syncAuthStateUI];
}

- (void)restoreAdminSessionFromStorage
{
    [self setAdminToken:[self sessionStorageValueForKey:[self adminStorageKeyToken]]];
}

- (void)handleAdminSessionExpired
{
    [self clearAdminToken];
    [self setStatus:@"Admin session expired (401). Please sign in again."];
}

- (void)requestJSONWithPath:(CPString)path
              endpointGroup:(CPString)group
                     method:(CPString)method
                queryParams:(id)queryParams
                 bodyObject:(id)bodyObject
              requiresAdmin:(BOOL)requiresAdmin
                 completion:(Function)completion
{
    var httpMethod = method || @"GET";

    if (requiresAdmin && (!_adminToken || _adminToken.length === 0))
    {
        if (completion)
            completion(401, nil, @"Admin authentication required");
        return;
    }

    var urlString = [_apiClient URLStringForPath:path endpointGroup:group queryParams:queryParams],
        xhr = new XMLHttpRequest(),
        bodyJSON = nil;

    xhr.open(String(httpMethod), String(urlString), YES);
    xhr.setRequestHeader("Accept", "application/json");
    if (requiresAdmin && _adminToken)
        xhr.setRequestHeader("Authorization", "Bearer " + String(_adminToken));

    if (bodyObject !== nil && bodyObject !== undefined)
    {
        xhr.setRequestHeader("Content-Type", "application/json");
        bodyJSON = JSON.stringify(bodyObject);
    }

    xhr.onreadystatechange = function()
    {
        if (xhr.readyState !== 4)
            return;

        var statusCode = xhr.status || 0,
            responseText = xhr.responseText || "",
            payload = nil,
            parseError = nil;

        if (responseText.length > 0)
        {
            try
            {
                payload = JSON.parse(responseText);
            }
            catch (e)
            {
                if (statusCode >= 200 && statusCode < 300)
                    payload = {rawText: responseText};
                else
                    parseError = @"Failed to parse JSON response";
            }
        }

        if (!payload && responseText.length === 0)
            payload = {};

        var errorMessage = nil;
        if (statusCode < 200 || statusCode >= 300)
            errorMessage = (payload && (payload.error || payload.message)) ? (payload.error || payload.message) : ("HTTP " + statusCode);
        else if (parseError)
            errorMessage = parseError;

        if (requiresAdmin && statusCode === 401)
            [self handleAdminSessionExpired];

        if (completion)
            completion(statusCode, payload, errorMessage);
    };

    xhr.onerror = function()
    {
        if (completion)
            completion(0, nil, @"Network error");
    };

    xhr.send(bodyJSON);
}

- (void)loginWithPassword:(CPString)password
{
    var trimmedPassword = [self trimmedString:password];
    if (!trimmedPassword || trimmedPassword.length === 0)
    {
        [self setStatus:@"Admin password is required"];
        return;
    }

    [self setStatus:@"Signing in..."];
    [self requestJSONWithPath:@"/login"
                endpointGroup:@"admin"
                       method:@"POST"
                  queryParams:nil
                   bodyObject:{password: trimmedPassword}
                requiresAdmin:NO
                   completion:function(statusCode, payload, errorMessage)
                   {
                       if (statusCode >= 200 && statusCode < 300 && payload && payload.token)
                       {
                           [self setAdminToken:payload.token];
                           [_passwordField setStringValue:@""];
                           [self setStatus:@"Signed in"];
                           [self loadOverviewStats];
                           return;
                       }

                       [self setStatus:[@"Admin login failed: " stringByAppendingString:(errorMessage || @"Unknown error")]];
                   }];
}

- (void)logoutAdminSession
{
    [self clearAdminToken];
    [self setStatus:@"Signed out"];
}

- (id)selectedAccount
{
    var row = [_accountsTable selectedRow];
    if (row < 0 || row >= _filteredAccounts.length)
        return nil;
    return _filteredAccounts[row];
}

- (id)selectedReport
{
    var row = [_reportsTable selectedRow];
    if (row < 0 || row >= _reports.length)
        return nil;
    return _reports[row];
}

- (id)selectedInvite
{
    var row = [_invitesTable selectedRow];
    if (row < 0 || row >= _invites.length)
        return nil;
    return _invites[row];
}

- (id)selectedModerationUser
{
    var row = [_moderationTable selectedRow];
    if (row < 0 || row >= _moderationUsers.length)
        return nil;
    return _moderationUsers[row];
}

- (void)loadOverviewStats
{
    [self setStatus:@"Loading admin overview..."];
    [self requestJSONWithPath:@"/stats"
                endpointGroup:@"admin"
                       method:@"GET"
                  queryParams:nil
                   bodyObject:nil
                requiresAdmin:YES
                   completion:function(statusCode, payload, errorMessage)
                   {
                       if (!(statusCode >= 200 && statusCode < 300))
                       {
                           [self setTextView:_overviewTextView content:[@"Failed to load overview: " stringByAppendingString:(errorMessage || @"Unknown error")]];
                           return;
                       }

                       var lines = [];
                       lines.push("Overview");
                       lines.push("========");
                       lines.push("");
                       lines.push("Accounts total: " + [self safeString:payload.accounts_total]);
                       lines.push("Repos total: " + [self safeString:payload.repos_total]);
                       lines.push("Records total: " + [self safeString:payload.records_total]);
                       lines.push("Blocks total: " + [self safeString:payload.blocks_total]);
                       lines.push("Blobs total: " + [self safeString:payload.blobs_total]);
                       lines.push("Blob size bytes: " + [self safeString:payload.blobs_size_bytes]);
                       lines.push("");
                       lines.push("Recent signups (7d): " + [self safeString:payload.recent_signups_7d]);
                       lines.push("Open reports: " + [self safeString:payload.reports_open]);
                       lines.push("Invite codes total: " + [self safeString:payload.invite_codes_total]);
                       lines.push("Invite codes active: " + [self safeString:payload.invite_codes_active]);
                       lines.push("");
                       lines.push("Raw payload:");
                       lines.push([self prettyJSON:payload]);

                       [self setTextView:_overviewTextView content:lines.join("\n")];
                       [self setStatus:@"Overview loaded"];
                   }];
}

- (void)applyAccountFilter
{
    var query = [[self trimmedString:[_accountsSearchField stringValue]] lowercaseString];
    if (!query || query.length === 0)
    {
        _filteredAccounts = _accounts.slice(0);
        [_accountsTable reloadData];
        return;
    }

    _filteredAccounts = [];
    for (var i = 0; i < _accounts.length; i++)
    {
        var account = _accounts[i];
        if (!account)
            continue;

        var handle = (account.handle || @"").toLowerCase(),
            did = (account.did || @"").toLowerCase(),
            email = (account.email || @"").toLowerCase();

        if (handle.indexOf(query) >= 0 || did.indexOf(query) >= 0 || email.indexOf(query) >= 0)
            _filteredAccounts.push(account);
    }

    [_accountsTable reloadData];
}

- (void)refreshSelectedAccountDetail
{
    var account = [self selectedAccount];
    if (!account)
    {
        [self setTextView:_accountsDetailTextView content:@"Select an account to view details."];
        return;
    }

    var lines = [];
    lines.push("Handle: " + [self safeString:account.handle || account.did]);
    lines.push("DID: " + [self safeString:account.did]);
    lines.push("Email: " + [self safeString:account.email]);
    lines.push("Created: " + [self safeString:account.created_at]);
    lines.push("Status: " + (account.deactivated ? "Disabled" : "Active"));
    lines.push("Invite enabled: " + (account.invite_enabled ? "Yes" : "No"));
    lines.push("");
    lines.push("Raw payload:");
    lines.push([self prettyJSON:account]);
    [self setTextView:_accountsDetailTextView content:lines.join("\n")];
}

- (void)loadAccounts
{
    [self setStatus:@"Loading accounts..."];
    [self requestJSONWithPath:@"/users"
                endpointGroup:@"admin"
                       method:@"GET"
                  queryParams:nil
                   bodyObject:nil
                requiresAdmin:YES
                   completion:function(statusCode, payload, errorMessage)
                   {
                       if (!(statusCode >= 200 && statusCode < 300))
                       {
                           [self setTextView:_accountsResultTextView content:[@"Failed to load accounts: " stringByAppendingString:(errorMessage || @"Unknown error")]];
                           return;
                       }

                       _accounts = (payload && payload.users) ? payload.users : [];
                       [self applyAccountFilter];
                       [self setStatus:[@"Accounts loaded: " stringByAppendingString:String(_accounts.length)]];
                       [self setTextView:_accountsResultTextView content:[@"Loaded accounts: " stringByAppendingString:String(_accounts.length)]];

                       if (_filteredAccounts.length > 0)
                       {
                           [_accountsTable selectRowIndexes:[CPIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
                           [self refreshSelectedAccountDetail];
                       }
                       else
                       {
                           [self setTextView:_accountsDetailTextView content:@"No accounts found."];
                       }
                   }];
}

- (void)performAccountInviteToggleForDid:(CPString)did enable:(BOOL)enable source:(CPString)source
{
    if (!did || did.length === 0)
        return;

    var path = enable ? @"/com.atproto.admin.enableAccountInvites" : @"/com.atproto.admin.disableAccountInvites";
    var verb = enable ? @"enabled" : @"disabled";
    [self requestJSONWithPath:path
                endpointGroup:@"xrpc"
                       method:@"POST"
                  queryParams:nil
                   bodyObject:{did: did}
                requiresAdmin:YES
                   completion:function(statusCode, payload, errorMessage)
                   {
                       if (!(statusCode >= 200 && statusCode < 300))
                       {
                           var failure = [@"Failed to toggle invites for " stringByAppendingString:did];
                           failure = [failure stringByAppendingString:[@" (" stringByAppendingString:source]];
                           failure = [failure stringByAppendingString:@")"];
                           failure = [failure stringByAppendingString:[@": " stringByAppendingString:(errorMessage || @"Unknown error")]];
                           if ([source isEqual:@"accounts"])
                               [self setTextView:_accountsResultTextView content:failure];
                           else
                               [self setTextView:_moderationResultTextView content:failure];
                           return;
                       }

                       var message = [@"Invite capability " stringByAppendingString:verb];
                       message = [message stringByAppendingString:[@" for " stringByAppendingString:did]];
                       if ([source isEqual:@"accounts"])
                           [self setTextView:_accountsResultTextView content:message];
                       else
                           [self setTextView:_moderationResultTextView content:message];

                       [self setStatus:message];
                       [self loadAccounts];
                       [self loadModerationUsers];
                   }];
}

- (void)showSelectedAccountInfo
{
    var account = [self selectedAccount];
    if (!account)
    {
        [self setTextView:_accountsResultTextView content:@"Select an account first."];
        return;
    }

    var lines = [];
    lines.push("Account Info");
    lines.push("============");
    lines.push("Handle: " + [self safeString:account.handle]);
    lines.push("DID: " + [self safeString:account.did]);
    lines.push("Email: " + [self safeString:account.email]);
    lines.push("Created: " + [self safeString:account.created_at]);
    lines.push("Deactivated: " + (account.deactivated ? "Yes" : "No"));
    lines.push("Invite enabled: " + (account.invite_enabled ? "Yes" : "No"));

    window.alert(lines.join("\n"));
}

- (void)loadReports
{
    [self setStatus:@"Loading reports..."];
    var query = {},
        statusFilter = [_reportsStatusFilterPopup titleOfSelectedItem],
        reasonFilter = [self trimmedString:[_reportsReasonFilterField stringValue]],
        subjectFilter = [self trimmedString:[_reportsSubjectFilterField stringValue]];

    if (statusFilter && ![statusFilter isEqual:@"all"])
        query.status = statusFilter;
    if (reasonFilter && reasonFilter.length > 0)
        query.reasonType = reasonFilter;
    if (subjectFilter && subjectFilter.length > 0)
        query.subjectDid = subjectFilter;
    query.limit = 50;

    [self requestJSONWithPath:@"/com.atproto.admin.getModerationReports"
                endpointGroup:@"xrpc"
                       method:@"GET"
                  queryParams:query
                   bodyObject:nil
                requiresAdmin:YES
                   completion:function(statusCode, payload, errorMessage)
                   {
                       if (!(statusCode >= 200 && statusCode < 300))
                       {
                           [self setTextView:_reportsResultTextView content:[@"Failed to load reports: " stringByAppendingString:(errorMessage || @"Unknown error")]];
                           return;
                       }

                       _reports = (payload && payload.reports) ? payload.reports : [];
                       [_reportsTable reloadData];
                       [self setStatus:[@"Reports loaded: " stringByAppendingString:String(_reports.length)]];
                       [self setTextView:_reportsResultTextView content:[@"Loaded reports: " stringByAppendingString:String(_reports.length)]];

                       if (_reports.length > 0)
                       {
                           [_reportsTable selectRowIndexes:[CPIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
                           [self refreshSelectedReportDetail];
                       }
                       else
                       {
                           [self setTextView:_reportsDetailTextView content:@"No reports for selected filters."];
                       }
                   }];
}

- (CPString)reportReasonLabel:(CPString)reasonType
{
    if ([reasonType isEqual:@"com.atproto.moderation.defs#reasonSpam"])
        return @"Spam";
    if ([reasonType isEqual:@"com.atproto.moderation.defs#reasonViolation"])
        return @"TOS Violation";
    if ([reasonType isEqual:@"com.atproto.moderation.defs#reasonMisleading"])
        return @"Misleading";
    if ([reasonType isEqual:@"com.atproto.moderation.defs#reasonSexual"])
        return @"Sexual Content";
    if ([reasonType isEqual:@"com.atproto.moderation.defs#reasonRude"])
        return @"Rude/Offensive";
    if ([reasonType isEqual:@"com.atproto.moderation.defs#reasonOther"])
        return @"Other";
    return reasonType || @"-";
}

- (void)refreshSelectedReportDetail
{
    var report = [self selectedReport];
    if (!report)
    {
        [self setTextView:_reportsDetailTextView content:@"Select a report to view details."];
        return;
    }

    var lines = [];
    lines.push("Report: " + [self safeString:report.report_id || report.id]);
    lines.push("Status: " + [self safeString:report.status]);
    lines.push("Reason: " + [self reportReasonLabel:report.reason_type]);
    lines.push("Reported by DID: " + [self safeString:report.reported_by_did]);
    lines.push("Subject type: " + [self safeString:report.subject_type]);
    lines.push("Subject DID: " + [self safeString:report.subject_did]);
    lines.push("Subject URI: " + [self safeString:report.subject_uri]);
    lines.push("Created: " + [self safeString:report.created_at]);
    lines.push("Resolved by: " + [self safeString:report.resolved_by_did]);
    lines.push("Resolved at: " + [self safeString:report.resolved_at]);
    lines.push("Resolution notes: " + [self safeString:report.resolution_notes]);
    lines.push("Reason details: " + [self safeString:report.reason]);
    lines.push("");
    lines.push("Raw payload:");
    lines.push([self prettyJSON:report]);
    [self setTextView:_reportsDetailTextView content:lines.join("\n")];
}

- (void)resolveSelectedReportWithStatus:(CPString)status
{
    var report = [self selectedReport];
    if (!report)
    {
        [self setTextView:_reportsResultTextView content:@"Select a report first."];
        return;
    }

    var reportID = report.report_id || report.id,
        notes = [self trimmedString:[_reportsNotesField stringValue]],
        body = {id: reportID, status: status};
    if (notes && notes.length > 0)
        body.notes = notes;

    [self requestJSONWithPath:@"/com.atproto.admin.resolveReport"
                endpointGroup:@"xrpc"
                       method:@"POST"
                  queryParams:nil
                   bodyObject:body
                requiresAdmin:YES
                   completion:function(statusCode, payload, errorMessage)
                   {
                       if (!(statusCode >= 200 && statusCode < 300))
                       {
                           [self setTextView:_reportsResultTextView content:[@"Failed to update report: " stringByAppendingString:(errorMessage || @"Unknown error")]];
                           return;
                       }

                       var message = [@"Report " stringByAppendingString:[self safeString:reportID]];
                       message = [message stringByAppendingString:[@" -> " stringByAppendingString:status]];
                       [self setTextView:_reportsResultTextView content:message];
                       [self setStatus:message];
                       [self loadReports];
                   }];
}

- (void)loadSystemStatus
{
    [self requestJSONWithPath:@"/stats"
                endpointGroup:@"admin"
                       method:@"GET"
                  queryParams:nil
                   bodyObject:nil
                requiresAdmin:YES
                   completion:function(statusCode, payload, errorMessage)
                   {
                       if (!(statusCode >= 200 && statusCode < 300))
                       {
                           [self setTextView:_systemStatusTextView content:[@"Failed to load system status: " stringByAppendingString:(errorMessage || @"Unknown error")]];
                           return;
                       }

                       var lines = [];
                       lines.push("Server Status: running");
                       lines.push("======================");
                       lines.push("Accounts: " + [self safeString:payload.accounts_total]);
                       lines.push("Repos: " + [self safeString:payload.repos_total]);
                       lines.push("Records: " + [self safeString:payload.records_total]);
                       lines.push("Blobs: " + [self safeString:payload.blobs_total]);
                       lines.push("Open reports: " + [self safeString:payload.reports_open]);
                       lines.push("Invite codes total: " + [self safeString:payload.invite_codes_total]);
                       lines.push("Invite codes active: " + [self safeString:payload.invite_codes_active]);
                       lines.push("");
                       lines.push("Raw payload:");
                       lines.push([self prettyJSON:payload]);
                       [self setTextView:_systemStatusTextView content:lines.join("\n")];
                   }];
}

- (void)loadAuditPreview
{
    [self requestJSONWithPath:@"/audit-log"
                endpointGroup:@"admin"
                       method:@"GET"
                  queryParams:{limit: 10}
                   bodyObject:nil
                requiresAdmin:YES
                   completion:function(statusCode, payload, errorMessage)
                   {
                       if (!(statusCode >= 200 && statusCode < 300))
                       {
                           [self setTextView:_auditPreviewTextView content:[@"Failed to load audit preview: " stringByAppendingString:(errorMessage || @"Unknown error")]];
                           return;
                       }

                       _auditEntries = (payload && payload.entries) ? payload.entries : [];
                       if (_auditEntries.length === 0)
                       {
                           [self setTextView:_auditPreviewTextView content:@"No audit entries."];
                           return;
                       }

                       var lines = [];
                       lines.push("Recent Admin Actions");
                       lines.push("====================");
                       lines.push("");

                       for (var i = 0; i < _auditEntries.length; i++)
                       {
                           var entry = _auditEntries[i];
                           lines.push(
                               [self safeString:entry.created_at] +
                               " | " +
                               [self safeString:entry.action] +
                               " | " +
                               [self abbreviatedString:(entry.subject_id || @"-") maxLength:48]
                           );
                       }

                       [self setTextView:_auditPreviewTextView content:lines.join("\n")];
                   }];
}

- (void)loadSystemPanel
{
    [self setStatus:@"Loading system panel..."];
    [self loadSystemStatus];
    [self loadAuditPreview];
}

- (void)loadInvites
{
    [self setStatus:@"Loading invite codes..."];
    [self requestJSONWithPath:@"/invites"
                endpointGroup:@"admin"
                       method:@"GET"
                  queryParams:nil
                   bodyObject:nil
                requiresAdmin:YES
                   completion:function(statusCode, payload, errorMessage)
                   {
                       if (!(statusCode >= 200 && statusCode < 300))
                       {
                           [self setTextView:_invitesResultTextView content:[@"Failed to load invites: " stringByAppendingString:(errorMessage || @"Unknown error")]];
                           return;
                       }

                       _invites = (payload && payload.invites) ? payload.invites : [];
                       [_invitesTable reloadData];
                       [self setStatus:[@"Invite codes loaded: " stringByAppendingString:String(_invites.length)]];
                       [self setTextView:_invitesResultTextView content:[@"Invite codes loaded: " stringByAppendingString:String(_invites.length)]];
                   }];
}

- (void)generateInviteCode
{
    var forAccount = [self trimmedString:[_inviteForAccountField stringValue]];
    if (!forAccount || forAccount.length === 0)
    {
        var selected = [self selectedAccount];
        forAccount = selected ? (selected.did || @"") : nil;
    }
    if (!forAccount || forAccount.length === 0)
        forAccount = [_sessionState currentDID] || @"";

    if (!forAccount || forAccount.length === 0)
    {
        [self setTextView:_invitesResultTextView content:@"Provide forAccount DID or select an account first."];
        return;
    }

    var usesValue = parseInt([self trimmedString:[_inviteUsesField stringValue]], 10);
    if (!usesValue || usesValue < 1)
        usesValue = 1;

    [self requestJSONWithPath:@"/invites"
                endpointGroup:@"admin"
                       method:@"POST"
                  queryParams:nil
                   bodyObject:{forAccount: forAccount, usesAvailable: usesValue}
                requiresAdmin:YES
                   completion:function(statusCode, payload, errorMessage)
                   {
                       if (!(statusCode >= 200 && statusCode < 300))
                       {
                           [self setTextView:_invitesResultTextView content:[@"Failed to generate invite code: " stringByAppendingString:(errorMessage || @"Unknown error")]];
                           return;
                       }

                       var code = payload ? payload.code : nil,
                           message = code ? ([@"New invite code: " stringByAppendingString:code]) : @"Invite code generated";
                       [self setTextView:_invitesResultTextView content:message];
                       [self setStatus:message];
                       [self loadInvites];
                   }];
}

- (void)disableSelectedInviteCode
{
    var invite = [self selectedInvite];
    if (!invite)
    {
        [self setTextView:_invitesResultTextView content:@"Select an invite code first."];
        return;
    }

    var code = invite.code || @"";
    if (!code || code.length === 0)
    {
        [self setTextView:_invitesResultTextView content:@"Selected invite has no code field."];
        return;
    }

    [self requestJSONWithPath:@"/invites/disable"
                endpointGroup:@"admin"
                       method:@"POST"
                  queryParams:nil
                   bodyObject:{code: code}
                requiresAdmin:YES
                   completion:function(statusCode, payload, errorMessage)
                   {
                       if (!(statusCode >= 200 && statusCode < 300))
                       {
                           [self setTextView:_invitesResultTextView content:[@"Failed to disable invite code: " stringByAppendingString:(errorMessage || @"Unknown error")]];
                           return;
                       }

                       var message = [@"Invite disabled: " stringByAppendingString:code];
                       [self setTextView:_invitesResultTextView content:message];
                       [self setStatus:message];
                       [self loadInvites];
                   }];
}

- (void)loadModerationUsers
{
    [self setStatus:@"Loading moderation accounts..."];
    [self requestJSONWithPath:@"/users"
                endpointGroup:@"admin"
                       method:@"GET"
                  queryParams:nil
                   bodyObject:nil
                requiresAdmin:YES
                   completion:function(statusCode, payload, errorMessage)
                   {
                       if (!(statusCode >= 200 && statusCode < 300))
                       {
                           [self setTextView:_moderationResultTextView content:[@"Failed to load moderation accounts: " stringByAppendingString:(errorMessage || @"Unknown error")]];
                           return;
                       }

                       _moderationUsers = (payload && payload.users) ? payload.users : [];
                       [_moderationTable reloadData];
                       [self setStatus:[@"Moderation accounts loaded: " stringByAppendingString:String(_moderationUsers.length)]];
                       [self setTextView:_moderationResultTextView content:[@"Moderation accounts loaded: " stringByAppendingString:String(_moderationUsers.length)]];
                   }];
}

- (void)ensureAuditModalWindow
{
    if (_auditModalWindow)
        return;

    _auditModalWindow = [[CPWindow alloc] initWithContentRect:CGRectMake(180.0, 120.0, 920.0, 620.0)
                                                     styleMask:CPTitledWindowMask | CPClosableWindowMask | CPResizableWindowMask];
    [_auditModalWindow setTitle:@"Admin Audit Log"];

    var contentView = [_auditModalWindow contentView];

    var filterLabel = [[CPTextField alloc] initWithFrame:CGRectMake(12.0, 12.0, 42.0, 18.0)];
    [filterLabel setStringValue:@"Action:"];
    [filterLabel setEditable:NO];
    [filterLabel setBezeled:NO];
    [filterLabel setDrawsBackground:NO];
    [contentView addSubview:filterLabel];

    _auditFilterPopup = [[CPPopUpButton alloc] initWithFrame:CGRectMake(58.0, 10.0, 180.0, 24.0)];
    [_auditFilterPopup addItemsWithTitles:[@"all,account.disable,account.enable,invite.create,report.resolve" componentsSeparatedByString:@","]];
    [_auditFilterPopup setTarget:self];
    [_auditFilterPopup setAction:@selector(handleAuditFilterChanged:)];
    [contentView addSubview:_auditFilterPopup];

    var refreshButton = [[CPButton alloc] initWithFrame:CGRectMake(246.0, 8.0, 70.0, 28.0)];
    [refreshButton setTitle:@"Refresh"];
    [refreshButton setTarget:self];
    [refreshButton setAction:@selector(handleRefreshAuditLog:)];
    [contentView addSubview:refreshButton];

    _auditModalTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(12.0, 44.0, 896.0, 562.0)
                                                         inView:contentView];
}

- (void)renderAuditModalEntries
{
    if (!_auditModalTextView)
        return;

    var actionFilter = _auditFilterPopup ? [_auditFilterPopup titleOfSelectedItem] : @"all",
        lines = [];

    lines.push("Full Audit Log");
    lines.push("==============");
    lines.push("");

    var renderedCount = 0;
    for (var i = 0; i < _auditEntries.length; i++)
    {
        var entry = _auditEntries[i],
            action = entry ? (entry.action || @"") : @"";

        if (actionFilter && ![actionFilter isEqual:@"all"] && ![action isEqual:actionFilter])
            continue;

        renderedCount += 1;
        lines.push("Time: " + [self safeString:entry.created_at]);
        lines.push("Admin DID: " + [self safeString:entry.admin_did]);
        lines.push("Action: " + [self safeString:entry.action]);
        lines.push("Subject: " + [self safeString:entry.subject_type] + " / " + [self safeString:entry.subject_id]);
        lines.push("Details: " + [self prettyJSON:(entry.details || {})]);
        lines.push("");
    }

    if (renderedCount === 0)
        lines.push("No audit entries matched current filter.");

    [self setTextView:_auditModalTextView content:lines.join("\n")];
}

- (void)loadFullAuditLog
{
    [self setStatus:@"Loading full audit log..."];
    [self requestJSONWithPath:@"/audit-log"
                endpointGroup:@"admin"
                       method:@"GET"
                  queryParams:{limit: 100}
                   bodyObject:nil
                requiresAdmin:YES
                   completion:function(statusCode, payload, errorMessage)
                   {
                       if (!(statusCode >= 200 && statusCode < 300))
                       {
                           [self setTextView:_auditModalTextView content:[@"Failed to load full audit log: " stringByAppendingString:(errorMessage || @"Unknown error")]];
                           return;
                       }

                       _auditEntries = (payload && payload.entries) ? payload.entries : [];
                       [self renderAuditModalEntries];
                       [self setStatus:[@"Full audit entries loaded: " stringByAppendingString:String(_auditEntries.length)]];
                   }];
}

#pragma mark - Actions

- (void)handleLogin:(id)sender
{
    [self loginWithPassword:[_passwordField stringValue]];
}

- (void)handleLogout:(id)sender
{
    [self logoutAdminSession];
}

- (void)handleOpenOverviewPanel:(id)sender
{
    [self selectTabWithIdentifier:@"overview"];
    [self loadOverviewStats];
}

- (void)handleOpenInvitesPanel:(id)sender
{
    [self selectTabWithIdentifier:@"invites"];
    [self loadInvites];
}

- (void)handleOpenModerationPanel:(id)sender
{
    [self selectTabWithIdentifier:@"moderation"];
    [self loadModerationUsers];
}

- (void)handleRefreshOverview:(id)sender
{
    [self loadOverviewStats];
}

- (void)handleSearchAccounts:(id)sender
{
    [self applyAccountFilter];
    [self refreshSelectedAccountDetail];
}

- (void)handleClearAccountSearch:(id)sender
{
    [_accountsSearchField setStringValue:@""];
    [self applyAccountFilter];
    [self refreshSelectedAccountDetail];
}

- (void)handleRefreshAccounts:(id)sender
{
    [self loadAccounts];
}

- (void)handleDisableSelectedAccountInvites:(id)sender
{
    var account = [self selectedAccount];
    if (!account)
    {
        [self setTextView:_accountsResultTextView content:@"Select an account first."];
        return;
    }

    var selfRef = self;
    [self confirmDestructiveWithTitle:@"Disable account invites?"
                      informativeText:@"This will prevent " + (account.handle || account.did) + " from generating new invite codes. Existing codes remain valid."
                        confirmHandler:function()
    {
        [selfRef performAccountInviteToggleForDid:(account.did || @"") enable:NO source:@"accounts"];
    }];
}

- (void)handleEnableSelectedAccountInvites:(id)sender
{
    var account = [self selectedAccount];
    if (!account)
    {
        [self setTextView:_accountsResultTextView content:@"Select an account first."];
        return;
    }
    [self performAccountInviteToggleForDid:(account.did || @"") enable:YES source:@"accounts"];
}

- (void)handleShowSelectedAccountInfo:(id)sender
{
    [self showSelectedAccountInfo];
}

- (void)handleLoadReports:(id)sender
{
    [self loadReports];
}

- (void)handleDismissSelectedReport:(id)sender
{
    [self resolveSelectedReportWithStatus:@"dismissed"];
}

- (void)handleResolveSelectedReport:(id)sender
{
    [self resolveSelectedReportWithStatus:@"resolved"];
}

- (void)handleRefreshSystem:(id)sender
{
    [self loadSystemPanel];
}

- (void)handleOpenFullAuditLog:(id)sender
{
    [self ensureAuditModalWindow];
    [_auditModalWindow orderFront:self];
    [self loadFullAuditLog];
}

- (void)handleManageInvitesFromSystem:(id)sender
{
    [self selectTabWithIdentifier:@"invites"];
    [self loadInvites];
}

- (void)handleLoadInvites:(id)sender
{
    [self loadInvites];
}

- (void)handleGenerateInviteCode:(id)sender
{
    [self generateInviteCode];
}

- (void)handleDisableSelectedInvite:(id)sender
{
    [self disableSelectedInviteCode];
}

- (void)handleLoadModeration:(id)sender
{
    [self loadModerationUsers];
}

- (void)handleDisableSelectedModerationAccount:(id)sender
{
    var user = [self selectedModerationUser];
    if (!user)
    {
        [self setTextView:_moderationResultTextView content:@"Select an account first."];
        return;
    }

    [self performAccountInviteToggleForDid:(user.did || @"") enable:NO source:@"moderation"];
}

- (void)handleEnableSelectedModerationAccount:(id)sender
{
    var user = [self selectedModerationUser];
    if (!user)
    {
        [self setTextView:_moderationResultTextView content:@"Select an account first."];
        return;
    }

    [self performAccountInviteToggleForDid:(user.did || @"") enable:YES source:@"moderation"];
}

- (void)handleAuditFilterChanged:(id)sender
{
    [self renderAuditModalEntries];
}

- (void)handleRefreshAuditLog:(id)sender
{
    [self loadFullAuditLog];
}

#pragma mark - CPTabView Delegate

- (void)tabView:(CPTabView)tabView didSelectTabViewItem:(CPTabViewItem)tabViewItem
{
    var identifier = [tabViewItem identifier];
    if ([identifier isEqual:@"overview"])
    {
        [self loadOverviewStats];
        return;
    }
    if ([identifier isEqual:@"accounts"])
    {
        [self loadAccounts];
        return;
    }
    if ([identifier isEqual:@"reports"])
    {
        [self loadReports];
        return;
    }
    if ([identifier isEqual:@"system"])
    {
        [self loadSystemPanel];
        return;
    }
    if ([identifier isEqual:@"invites"])
    {
        [self loadInvites];
        return;
    }
    if ([identifier isEqual:@"moderation"])
    {
        [self loadModerationUsers];
    }
}

#pragma mark - CPTableView Data Source

- (int)numberOfRowsInTableView:(CPTableView)tableView
{
    if (tableView === _accountsTable)
        return _filteredAccounts.length;
    if (tableView === _reportsTable)
        return _reports.length;
    if (tableView === _invitesTable)
        return _invites.length;
    if (tableView === _moderationTable)
        return _moderationUsers.length;
    return 0;
}

- (id)tableView:(CPTableView)tableView objectValueForTableColumn:(CPTableColumn)tableColumn row:(int)row
{
    if (tableView === _accountsTable)
    {
        var account = _filteredAccounts[row],
            accountIdentifier = [tableColumn identifier];
        if ([accountIdentifier isEqual:@"account_handle"])
            return account ? (account.handle || @"") : @"";
        if ([accountIdentifier isEqual:@"account_did"])
            return account ? (account.did || @"") : @"";
    }

    if (tableView === _reportsTable)
    {
        var report = _reports[row],
            reportIdentifier = [tableColumn identifier];
        if ([reportIdentifier isEqual:@"report_status"])
            return report ? (report.status || @"") : @"";
        if ([reportIdentifier isEqual:@"report_reason"])
            return [self reportReasonLabel:(report ? report.reason_type : @"")];
        if ([reportIdentifier isEqual:@"report_subject"])
            return report ? (report.subject_did || report.subject_uri || @"") : @"";
    }

    if (tableView === _invitesTable)
    {
        var invite = _invites[row],
            inviteIdentifier = [tableColumn identifier];
        if ([inviteIdentifier isEqual:@"invite_code"])
            return invite ? (invite.code || @"") : @"";
        if ([inviteIdentifier isEqual:@"invite_created_by"])
            return invite ? (invite.created_by || @"") : @"";
        if ([inviteIdentifier isEqual:@"invite_uses"])
        {
            if (!invite)
                return @"";
            return String(invite.uses || 0) + "/" + String(invite.max_uses || 1);
        }
        if ([inviteIdentifier isEqual:@"invite_status"])
            return invite ? (invite.disabled ? @"Disabled" : @"Active") : @"";
        if ([inviteIdentifier isEqual:@"invite_created_at"])
            return invite ? (invite.created_at || @"") : @"";
    }

    if (tableView === _moderationTable)
    {
        var user = _moderationUsers[row],
            userIdentifier = [tableColumn identifier];
        if ([userIdentifier isEqual:@"moderation_handle"])
            return user ? (user.handle || @"") : @"";
        if ([userIdentifier isEqual:@"moderation_did"])
            return user ? (user.did || @"") : @"";
        if ([userIdentifier isEqual:@"moderation_status"])
            return user ? (user.deactivated ? @"Disabled" : @"Active") : @"";
    }

    return @"";
}

#pragma mark - CPTableView Delegate

- (void)tableViewSelectionDidChange:(CPNotification)notification
{
    var tableView = [notification object];
    if (tableView === _accountsTable)
    {
        [self refreshSelectedAccountDetail];
        return;
    }
    if (tableView === _reportsTable)
    {
        [self refreshSelectedReportDetail];
        return;
    }
}

@end

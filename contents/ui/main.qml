import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.extras 2.0 as PlasmaExtras
import org.kde.kirigami 2.20 as Kirigami

PlasmoidItem {
    id: root

    Layout.minimumWidth: 350
    Layout.minimumHeight: 200
    Layout.preferredWidth: 450
    Layout.preferredHeight: 700

    // Configuration properties
    property string clientId: plasmoid.configuration.clientId || ""
    property string clientSecret: plasmoid.configuration.clientSecret || ""
    property string accessToken: plasmoid.configuration.accessToken || ""
    property string refreshToken: plasmoid.configuration.refreshToken || ""

    // NEW: Enhanced session tracking
    property string lastAuthState: plasmoid.configuration.lastAuthState || ""
    property int tokenExpiryTime: parseInt(plasmoid.configuration.tokenExpiryTime || "0")
    property int lastSuccessfulRefresh: parseInt(plasmoid.configuration.lastSuccessfulRefresh || "0")

    // API endpoints
    property string authBaseUrl: "https://accounts.spotify.com/authorize"
    property string tokenUrl: "https://accounts.spotify.com/api/token"
    property string queueApiUrl: "https://api.spotify.com/v1/me/player/queue"
    property string redirectUri: "https://example.com/callback"
    property string scopes: "user-read-currently-playing user-read-playback-state"

    // State management
    property var queueData: []
    property bool isAuthenticated: false
    property bool isLoading: false
    property string currentAuthState: ""

    // NEW: Enhanced token refresh properties
    property int tokenRefreshTime: 0

    // Generate the authorization URL (standard OAuth without PKCE)
    function getAuthUrl() {
        // NEW: Generate and store current auth state for security
        currentAuthState = generateRandomString(16);
        plasmoid.configuration.lastAuthState = currentAuthState;
        
        var params = [
            "response_type=code",
            "client_id=" + encodeURIComponent(clientId),
            "scope=" + encodeURIComponent(scopes),
            "redirect_uri=" + encodeURIComponent(redirectUri),
            "state=" + encodeURIComponent(currentAuthState),
            "show_dialog=true"
        ].join("&");

        return authBaseUrl + "?" + params;
    }

    function generateRandomString(length) {
        var result = '';
        var characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
        for (var i = 0; i < length; i++) {
            result += characters.charAt(Math.floor(Math.random() * characters.length));
        }
        return result;
    }

    // NEW: Function to extract code from full redirect URL
    function extractCodeFromUrl(url) {
        try {
            var codeMatch = url.match(/[?&]code=([^&]*)/);
            var stateMatch = url.match(/[?&]state=([^&]*)/);
            
            if (codeMatch && stateMatch) {
                var extractedCode = decodeURIComponent(codeMatch[1]);
                var extractedState = decodeURIComponent(stateMatch[1]);
                
                // Verify state matches for security (if we have current state)
                if (currentAuthState && extractedState !== currentAuthState) {
                    console.log("State mismatch in URL - possible security issue");
                    showError("Security error: Invalid state parameter");
                    return null;
                }
                
                return extractedCode;
            }
        } catch (e) {
            console.log("Error extracting code from URL:", e.message);
        }
        return null;
    }

    function openAuthUrl() {
        if (!clientId || !clientSecret) {
            showError("Please configure your Client ID and Client Secret in widget settings");
            return;
        }

        var authUrl = getAuthUrl();
        Qt.openUrlExternally(authUrl);
        showMessage("🌐 Browser opened. Paste the full redirect URL or just the code below.");
        authArea.visible = true;
    }

    function exchangeCodeForToken(code) {
        if (!code || code.trim().length === 0) {
            showError("Please provide the authorization code");
            return;
        }

        if (!clientId || !clientSecret) {
            showError("Please configure Client ID and Secret in widget settings");
            return;
        }

        isLoading = true;
        showMessage("🔄 Exchanging code for access token...");

        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            isLoading = false;
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var response = JSON.parse(xhr.responseText);
                        accessToken = response.access_token || "";
                        refreshToken = response.refresh_token || "";

                        if (accessToken) {
                            // Enhanced token persistence
                            var currentTime = Math.floor(Date.now() / 1000);
                            tokenExpiryTime = currentTime + (response.expires_in || 3600);
                            tokenRefreshTime = currentTime + Math.max(300, (response.expires_in || 3600) - 300); // Refresh 5 min early
                            lastSuccessfulRefresh = currentTime;

                            // Save tokens with enhanced metadata
                            plasmoid.configuration.accessToken = accessToken;
                            if (refreshToken) {
                                plasmoid.configuration.refreshToken = refreshToken;
                            }
                            plasmoid.configuration.tokenExpiryTime = tokenExpiryTime.toString();
                            plasmoid.configuration.lastSuccessfulRefresh = lastSuccessfulRefresh.toString();

                            isAuthenticated = true;
                            authArea.visible = false;
                            authCodeField.text = "";

                            showMessage("✅ Authentication successful! Session will persist longer.");
                            fetchQueue();
                            refreshTimer.start();
                            // NEW: Start proactive refresh timer
                            proactiveRefreshTimer.start();
                        } else {
                            showError("No access token received");
                        }
                    } catch (e) {
                        showError("Failed to parse token response: " + e.message);
                    }
                } else {
                    var errorMsg = "Token exchange failed: " + xhr.status;
                    try {
                        var errorResponse = JSON.parse(xhr.responseText);
                        if (errorResponse.error_description) {
                            errorMsg += " - " + errorResponse.error_description;
                        }
                    } catch (e) {
                        // Ignore parsing errors
                    }
                    showError(errorMsg);
                    console.log("Token exchange error:", xhr.responseText);
                }
            }
        }

        var params = [
            "grant_type=authorization_code",
            "client_id=" + encodeURIComponent(clientId),
            "client_secret=" + encodeURIComponent(clientSecret),
            "code=" + encodeURIComponent(code.trim()),
            "redirect_uri=" + encodeURIComponent(redirectUri)
        ].join("&");

        xhr.open("POST", tokenUrl);
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        xhr.send(params);
    }

    // Enhanced refresh token handling
    function refreshAccessToken() {
        if (!refreshToken) {
            showMessage("No refresh token available. Please re-authenticate.");
            disconnect();
            return;
        }

        isLoading = true;
        showMessage("🔄 Refreshing access token...");

        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            isLoading = false;
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var response = JSON.parse(xhr.responseText);
                        accessToken = response.access_token || accessToken;

                        // Update refresh token if provided (some providers rotate refresh tokens)
                        if (response.refresh_token) {
                            refreshToken = response.refresh_token;
                            plasmoid.configuration.refreshToken = refreshToken;
                        }

                        // Enhanced token tracking
                        var currentTime = Math.floor(Date.now() / 1000);
                        tokenExpiryTime = currentTime + (response.expires_in || 3600);
                        tokenRefreshTime = currentTime + Math.max(300, (response.expires_in || 3600) - 300);
                        lastSuccessfulRefresh = currentTime;

                        // Save enhanced metadata
                        plasmoid.configuration.accessToken = accessToken;
                        plasmoid.configuration.tokenExpiryTime = tokenExpiryTime.toString();
                        plasmoid.configuration.lastSuccessfulRefresh = lastSuccessfulRefresh.toString();

                        isAuthenticated = true;
                        showMessage("🔄 Token refreshed successfully");
                        fetchQueue();
                    } catch (e) {
                        showError("Failed to refresh token: " + e.message);
                        disconnect();
                    }
                } else if (xhr.status === 400) {
                    showError("Refresh token expired. Please re-authenticate.");
                    disconnect();
                } else {
                    showError("Token refresh failed: " + xhr.status + ". Please re-authenticate.");
                    disconnect();
                }
            }
        }

        var params = [
            "grant_type=refresh_token",
            "refresh_token=" + encodeURIComponent(refreshToken),
            "client_id=" + encodeURIComponent(clientId),
            "client_secret=" + encodeURIComponent(clientSecret)
        ].join("&");

        xhr.open("POST", tokenUrl);
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        xhr.send(params);
    }

    function isTokenExpired() {
        if (tokenExpiryTime === 0) return false;
        var currentTime = Math.floor(Date.now() / 1000);
        return currentTime >= tokenExpiryTime;
    }

    // NEW: Check if we should proactively refresh token
    function shouldProactivelyRefresh() {
        if (tokenRefreshTime === 0) return false;
        var currentTime = Math.floor(Date.now() / 1000);
        return currentTime >= tokenRefreshTime;
    }

    function fetchQueue() {
        if (!accessToken) {
            showError("No access token available");
            return;
        }

        if (isTokenExpired()) {
            showMessage("🔄 Token expired, refreshing...");
            refreshAccessToken();
            return;
        }

        isLoading = true;

        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            isLoading = false;
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var response = JSON.parse(xhr.responseText);
                        queueData = response.queue || [];
                        updateQueueDisplay();
                        showMessage("📋 Queue updated (" + queueData.length + " tracks)");
                    } catch (e) {
                        showError("Failed to parse queue data: " + e.message);
                    }
                } else if (xhr.status === 401) {
                    showMessage("🔄 Token expired, refreshing...");
                    refreshAccessToken();
                } else if (xhr.status === 404) {
                    showMessage("🎵 No active Spotify session. Start playing music first.");
                    queueData = [];
                    updateQueueDisplay();
                } else if (xhr.status === 403) {
                    showError("⭐ Spotify Premium required for queue access");
                } else {
                    showError("API Error " + xhr.status + ": " + xhr.statusText);
                    console.log("Queue API Error:", xhr.responseText);
                }
            }
        }

        xhr.open("GET", queueApiUrl);
        xhr.setRequestHeader("Authorization", "Bearer " + accessToken);
        xhr.send();
    }

    function updateQueueDisplay() {
        queueListModel.clear();

        if (!queueData || queueData.length === 0) {
            return;
        }

        for (var i = 0; i < Math.min(queueData.length, 25); i++) {
            var track = queueData[i];
            if (!track) continue;

            var artists = "Unknown Artist";
            if (track.artists && track.artists.length > 0) {
                artists = track.artists.map(function(a) { return a.name; }).join(", ");
            }

            var albumName = "Unknown Album";
            if (track.album) {
                albumName = track.album.name || "Unknown Album";
            }

            queueListModel.append({
                trackName: track.name || "Unknown Track",
                artistName: artists,
                albumName: albumName,
                duration: formatDuration(track.duration_ms),
                explicit: track.explicit || false
            });
        }
    }

    function formatDuration(ms) {
        if (!ms || ms === 0) return "0:00";
        var totalSeconds = Math.floor(ms / 1000);
        var minutes = Math.floor(totalSeconds / 60);
        var seconds = totalSeconds % 60;
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
    }

    function showError(message) {
        statusText.text = message;
        statusText.color = Kirigami.Theme.negativeTextColor;
    }

    function showMessage(message) {
        statusText.text = message;
        statusText.color = Kirigami.Theme.textColor;
    }

    function disconnect() {
        // Stop refresh timer
        refreshTimer.stop();
        // NEW: Stop proactive refresh timer
        proactiveRefreshTimer.stop();

        // Clear state
        isAuthenticated = false;
        accessToken = "";
        refreshToken = "";
        tokenExpiryTime = 0;
        tokenRefreshTime = 0;
        lastSuccessfulRefresh = 0;
        currentAuthState = "";

        // Clear stored configuration
        plasmoid.configuration.accessToken = "";
        plasmoid.configuration.refreshToken = "";
        plasmoid.configuration.tokenExpiryTime = "";
        plasmoid.configuration.lastSuccessfulRefresh = "";
        plasmoid.configuration.lastAuthState = "";

        // Clear UI
        queueListModel.clear();
        queueData = [];
        authArea.visible = false;
        authCodeField.text = "";

        showMessage("🔴 Disconnected from Spotify");
    }

    // Enhanced initialization with better token recovery
    Component.onCompleted: {
        // Try to restore enhanced token metadata
        lastAuthState = plasmoid.configuration.lastAuthState || "";

        if (accessToken && !isTokenExpired()) {
            isAuthenticated = true;
            fetchQueue();
            refreshTimer.start();
            proactiveRefreshTimer.start();
            showMessage("🟢 Session restored successfully");
        } else if (accessToken && isTokenExpired()) {
            showMessage("⏰ Previous session expired");
            if (refreshToken) {
                showMessage("🔄 Attempting to restore session with refresh token...");
                refreshAccessToken();
            } else {
                showMessage("Ready to connect. Click 'Get Code' to start.");
            }
        } else {
            showMessage("👋 Ready to connect with enhanced authentication");
        }
    }

    // Auto-refresh timer (10 seconds)
    Timer {
        id: refreshTimer
        interval: 10000
        repeat: true
        running: false
        onTriggered: {
            if (isAuthenticated && !isTokenExpired()) {
                fetchQueue();
            } else {
                disconnect();
            }
        }
    }

    // NEW: Proactive token refresh timer (checks every 5 minutes)
    Timer {
        id: proactiveRefreshTimer
        interval: 300000 // 5 minutes
        repeat: true
        running: false
        onTriggered: {
            if (isAuthenticated && shouldProactivelyRefresh() && refreshToken) {
                console.log("Proactively refreshing token to maintain session");
                refreshAccessToken();
            }
        }
    }

    // Queue list model
    ListModel {
        id: queueListModel
    }

    // Main UI Layout
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // Header Row
        RowLayout {
            Layout.fillWidth: true

            Kirigami.Icon {
                source: "media-playlist-append"
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                PlasmaExtras.Heading {
                    text: "Spotify Queue"
                    level: 3
                }

                PlasmaComponents3.Label {
                    text: isAuthenticated ? "🟢 Connected (Enhanced)" : "🔴 Not connected"
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.8
                }
            }

            PlasmaComponents3.Button {
                icon.name: "view-refresh"
                text: "Refresh"
                enabled: isAuthenticated && !isLoading
                onClicked: fetchQueue()
            }

            PlasmaComponents3.Button {
                icon.name: isAuthenticated ? "network-disconnect" : "network-connect"
                text: isAuthenticated ? "Disconnect" : "Get Code"
                onClicked: {
                    if (isAuthenticated) {
                        disconnect();
                    } else {
                        openAuthUrl();
                    }
                }
            }
        }

        // Status Text
        PlasmaComponents3.Label {
            id: statusText
            Layout.fillWidth: true
            text: "Ready to connect with enhanced authentication"
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }

        // Enhanced Authorization Code Input Area
        Rectangle {
            id: authArea
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            visible: false
            color: Kirigami.Theme.backgroundColor
            border.color: Kirigami.Theme.highlightColor
            border.width: 2
            radius: 8

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                PlasmaExtras.Heading {
                    text: "🔑 Enhanced Authorization"
                    level: 4
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                }

                PlasmaComponents3.Label {
                    text: "✨ Smart Input: Paste either the full redirect URL or just the code!"
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: Kirigami.Theme.positiveTextColor
                    horizontalAlignment: Text.AlignHCenter
                }

                PlasmaComponents3.Label {
                    text: "After authorizing in browser:\n• Copy the ENTIRE redirect URL and paste below (auto-extracts code)\n• OR copy just the authorization code manually"
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.8
                }

                PlasmaComponents3.Label {
                    text: "Example URL: https://example.com/callback?code=AQBxxxxx...&state=xxxxx"
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.6
                    font.family: "monospace"
                }

                RowLayout {
                    Layout.fillWidth: true

                    PlasmaComponents3.TextField {
                        id: authCodeField
                        Layout.fillWidth: true
                        placeholderText: "Paste full URL or authorization code here..."
                        selectByMouse: true

                        // NEW: Auto-detect and extract code when text changes
                        onTextChanged: {
                            if (text.length > 10) {
                                // Check if it's a full URL
                                if (text.includes("example.com/callback") && text.includes("code=")) {
                                    var extractedCode = extractCodeFromUrl(text);
                                    if (extractedCode) {
                                        text = extractedCode;
                                        showMessage("✅ Code extracted from URL automatically!");
                                    }
                                }
                            }
                        }
                    }

                    PlasmaComponents3.Button {
                        text: "Submit"
                        enabled: authCodeField.text.length > 10 && !isLoading
                        onClicked: exchangeCodeForToken(authCodeField.text)
                    }
                }
            }
        }

        // Loading Indicator
        PlasmaComponents3.BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            visible: isLoading
        }

        // Queue List (unchanged - works perfectly)
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: queueListView
                model: queueListModel
                spacing: 1

                delegate: Rectangle {
                    width: queueListView.width
                    height: 60
                    color: index % 2 === 0 ? "transparent" : Kirigami.Theme.alternateBackgroundColor

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 12

                        // Track number
                        Rectangle {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            color: Kirigami.Theme.highlightColor
                            radius: 12

                            PlasmaComponents3.Label {
                                anchors.centerIn: parent
                                text: (index + 1).toString()
                                color: Kirigami.Theme.highlightedTextColor
                                font.bold: true
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }
                        }

                        // Track info
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true

                                PlasmaComponents3.Label {
                                    text: model.trackName || "Unknown Track"
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                PlasmaComponents3.Label {
                                    text: "🅴"
                                    visible: model.explicit
                                    color: Kirigami.Theme.negativeTextColor
                                }
                            }

                            PlasmaComponents3.Label {
                                text: (model.artistName || "Unknown Artist") + " • " + (model.albumName || "Unknown Album")
                                opacity: 0.7
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }
                        }

                        // Duration
                        PlasmaComponents3.Label {
                            text: model.duration || "0:00"
                            opacity: 0.7
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                }

                // Empty state - authenticated
                PlasmaExtras.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - 32

                    visible: queueListModel.count === 0 && isAuthenticated && !isLoading

                    iconName: "media-playlist-append"
                    text: "Queue is empty"
                    explanation: "Start playing music on Spotify to see your queue"
                }

                // Not connected state
                PlasmaExtras.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - 32

                    visible: !isAuthenticated && !isLoading && !authArea.visible

                    iconName: "network-disconnect"
                    text: "Connect to Spotify"
                    explanation: "Enhanced authentication with auto-extraction"
                }
            }
        }

        // Enhanced Footer with session info
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: {
                if (queueListModel.count > 0) {
                    return "📋 " + queueListModel.count + " tracks • 🔄 Enhanced session";
                } else if (isAuthenticated) {
                    var timeSinceRefresh = Math.floor((Date.now() / 1000) - lastSuccessfulRefresh);
                    var timeString = timeSinceRefresh < 60 ? "just now" : Math.floor(timeSinceRefresh / 60) + "m ago";
                    return "🔄 Session active (last refresh: " + timeString + ")";
                } else {
                    return "";
                }
            }
            horizontalAlignment: Text.AlignHCenter
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.6
            visible: text !== ""
        }
    }
}
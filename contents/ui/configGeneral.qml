import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import org.kde.kirigami 2.20 as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_clientId: clientIdField.text
    property alias cfg_clientSecret: clientSecretField.text

    Kirigami.FormLayout {
        anchors.fill: parent

        Kirigami.Separator {
            Kirigami.FormData.label: "Enhanced Auto-Authentication Setup"
            Kirigami.FormData.isSection: true
        }

        TextField {
            id: clientIdField
            Kirigami.FormData.label: "Client ID:"
            placeholderText: "Your Spotify app Client ID"
        }

        TextField {
            id: clientSecretField
            Kirigami.FormData.label: "Client Secret:"
            placeholderText: "Your Spotify app Client Secret"
            echoMode: TextInput.Password
        }

        Kirigami.Separator {
            Kirigami.FormData.label: "Enhanced Features"
            Kirigami.FormData.isSection: true
        }

        Label {
            Kirigami.FormData.label: "New Auto-Features:"
            text: "🔗 Automatic code extraction from URLs\n" +
                  "🔄 Proactive token refresh (extends sessions)\n" +
                  "💾 Enhanced session persistence\n" +
                  "⚡ Reduced re-authentication needs\n" +
                  "🛡️ State parameter verification for security"
            wrapMode: Text.Wrap
            Layout.maximumWidth: 500
            color: Kirigami.Theme.positiveTextColor
        }

        Label {
            Kirigami.FormData.label: "Setup (Same as Before):"
            text: "1. Go to Spotify Developer Dashboard\n" +
                  "2. Create a new app\n" +
                  "3. Set redirect URI to: https://example.com/callback\n" +
                  "4. Copy Client ID and Client Secret here\n" +
                  "5. Use enhanced 'Get Code' button in widget"
            wrapMode: Text.Wrap
            Layout.maximumWidth: 500
        }

        Label {
            Kirigami.FormData.label: "How Auto-Extraction Works:"
            text: "After clicking 'Get Code' and authorizing:\n" +
                  "• Simply paste the ENTIRE redirect URL into the widget\n" +
                  "• Widget automatically extracts the authorization code\n" +
                  "• Or paste just the code manually as before\n" +
                  "• Sessions last much longer with proactive refresh"
            wrapMode: Text.Wrap
            Layout.maximumWidth: 500
            color: Kirigami.Theme.neutralTextColor
        }

        Button {
            text: "Open Spotify Developer Dashboard"
            onClicked: Qt.openUrlExternally("https://developer.spotify.com/dashboard")
        }
    }
}
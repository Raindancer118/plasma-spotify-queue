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
            Kirigami.FormData.label: "Simple OAuth Setup"
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
            Kirigami.FormData.label: "Setup Instructions"
            Kirigami.FormData.isSection: true
        }

        Label {
            Kirigami.FormData.label: "Simple Setup:"
            text: "1. Go to Spotify Developer Dashboard\n" +
                  "2. Create a new app\n" +
                  "3. Set redirect URI to: https://example.com/callback\n" +
                  "4. Copy Client ID and Client Secret here\n" +
                  "5. Use 'Get Code' button in widget"
            wrapMode: Text.Wrap
            Layout.maximumWidth: 500
        }

        Label {
            Kirigami.FormData.label: "Why this works:"
            text: "• Uses standard Authorization Code flow\n" +
                  "• No PKCE complications (S256 issues avoided)\n" +
                  "• Clear redirect to example.com shows code easily\n" +
                  "• Reliable and battle-tested approach"
            wrapMode: Text.Wrap
            Layout.maximumWidth: 500
            color: Kirigami.Theme.positiveTextColor
        }

        Button {
            text: "Open Spotify Developer Dashboard"
            onClicked: Qt.openUrlExternally("https://developer.spotify.com/dashboard")
        }
    }
}
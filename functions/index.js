const functions = require("firebase-functions/v1");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

exports.sendIncomingCallAlert = functions.firestore
    .document("calls/{callId}")
    .onCreate(async (snap, context) => {
    
    const callData = snap.data();
    if (!callData) return;

    const calleeId = callData.calleeId;
    const callerName = callData.callerName || 'Someone';

    try {
        const userDoc = await getFirestore().collection('users').doc(calleeId).get();
        const userData = userDoc.data();
        
        if (!userData || !userData.fcmToken || userData.notificationsEnabled === false) {
            console.log(`Notifications disabled or no FCM token for user ${calleeId}`);
            return;
        }

        const message = {
            notification: {
                title: 'Incoming Call',
                body: `You have an incoming call from ${callerName}!`
            },
            webpush: {
                fcmOptions: {
                    link: "/"
                }
            },
            token: userData.fcmToken
        };

        const response = await getMessaging().send(message);
        console.log('Successfully sent message:', response);
    } catch (error) {
        console.error('Error sending message:', error);
    }
});

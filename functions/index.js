const {onRequest, onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {setGlobalOptions} = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();
setGlobalOptions({maxInstances: 10});

// ─────────────────────────────────────────────
// Apple Sign-In callback redirect
// ─────────────────────────────────────────────

exports.appleSignInCallback = onRequest((req, res) => {
  const params = new URLSearchParams(req.body).toString();
  const intentUrl =
    `intent://callback?${params}` +
    `#Intent;package=com.silentmorse.messenger;` +
    `scheme=signinwithapple;end`;
  res.redirect(intentUrl);
});

// ─────────────────────────────────────────────
// createChat — get or create a 1-on-1 chat
// ─────────────────────────────────────────────

exports.createChat = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const myUserId = request.auth.uid;
  const targetUserId = request.data.targetUserId;

  if (!targetUserId || typeof targetUserId !== "string") {
    throw new HttpsError(
        "invalid-argument", "targetUserId is required.");
  }
  if (myUserId === targetUserId) {
    throw new HttpsError(
        "invalid-argument", "Cannot start a chat with yourself.");
  }

  const db = admin.firestore();

  // Look for ANY existing 1-on-1 chat between the two users (any status).
  // We never create a second document for the same pair — instead we
  // reactivate a declined/pending chat or return the existing active one.
  const snapshot = await db
      .collection("chats")
      .where("participants", "array-contains", myUserId)
      .get();

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const {participants, isGroup} = data;
    if (
      !isGroup &&
      Array.isArray(participants) &&
      participants.length === 2 &&
      participants.includes(targetUserId)
    ) {
      // Reactivate if it was previously declined or reset to pending.
      const status = (data.status || "ACTIVE").toUpperCase();
      if (status === "DECLINED") {
        await doc.ref.update({
          status: "PENDING",
          requesterId: myUserId,
          lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      return {chatId: doc.id};
    }
  }

  // Look up sender display name for the request notification.
  const senderDoc = await db.collection("users").doc(myUserId).get();
  const senderName = senderDoc.exists ?
    (senderDoc.data().displayName || "Someone") :
    "Someone";

  // No existing chat — create one as a pending request.
  const chatRef = await db.collection("chats").add({
    participants: [myUserId, targetUserId],
    name: "",
    isGroup: false,
    status: "PENDING",
    requesterId: myUserId,
    lastMessage: "",
    lastMessageBy: "",
    lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Notify the receiver about the chat request (with banner + sound).
  const receiverDoc = await db.collection("users").doc(targetUserId).get();
  const receiverToken = receiverDoc.exists ?
    receiverDoc.data().fcmToken : null;

  if (receiverToken) {
    // Use the default FCM channel so no custom channel registration is needed.
    await admin.messaging().send({
      token: receiverToken,
      notification: {
        title: "Chat request from " + senderName,
        body: senderName + " wants to chat silently with you.",
      },
      android: {priority: "high"},
      data: {chatId: chatRef.id, type: "chat_request", senderName},
    });
  }

  return {chatId: chatRef.id};
});

// ─────────────────────────────────────────────
// sendMessageNotification — notify receiver on new message
// ─────────────────────────────────────────────

exports.sendMessageNotification = onDocumentCreated(
    "chats/{chatId}/messages/{messageId}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const msg = snap.data();
      const {chatId} = event.params;

      const senderId = msg.senderId;
      const text = msg.text || "";
      if (!senderId || !text) return;

      const db = admin.firestore();
      const chatDoc = await db.collection("chats").doc(chatId).get();
      if (!chatDoc.exists) return;

      const chatStatus = chatDoc.data().status || "ACTIVE";
      if (chatStatus !== "ACTIVE") return;

      const participants = chatDoc.data().participants || [];
      const recipientIds = participants.filter((id) => id !== senderId);
      if (recipientIds.length === 0) return;

      const morse = msg.morse || "";
      const isGroup = !!chatDoc.data().isGroup;
      const chatName = (chatDoc.data().name || "").trim();
      const chatLabel = isGroup ?
        (chatName || "Group") :
        "Direct";

      let senderName = (msg.senderDisplayName || "").trim();
      if (!senderName) {
        const senderDoc = await db.collection("users").doc(senderId).get();
        senderName = senderDoc.exists ?
          (senderDoc.data().displayName || "").trim() :
          "";
      }
      if (!senderName) senderName = "Someone";

      const notificationTitle = isGroup ?
        (chatName || "Group") :
        senderName;
      const notificationBody = text.length > 120 ?
        text.slice(0, 117) + "…" :
        text;

      const messaging = admin.messaging();
      const sends = recipientIds.map(async (recipientId) => {
        const userDoc = await db.collection("users").doc(recipientId).get();
        if (!userDoc.exists) return;
        if (userDoc.data().receiveIncoming === false) return;
        const token = userDoc.data().fcmToken;
        if (!token) return;

        const data = {
          chatId,
          senderId,
          type: "message",
          morse,
          text,
          senderName,
          isGroup: isGroup ? "1" : "0",
          chatName: chatLabel,
        };

        await messaging.send({
          token,
          notification: {
            title: notificationTitle,
            body: notificationBody,
          },
          android: {priority: "high"},
          data,
        });
      });

      await Promise.allSettled(sends);

      // Brief delay so clients can observe the message before ephemeral delete.
      await new Promise((r) => setTimeout(r, 2000));

      try {
        await snap.ref.delete();
      } catch (e) {
        console.error("sendMessageNotification: delete message failed", e);
      }
    },
);

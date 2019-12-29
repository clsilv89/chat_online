import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _verifyLogInState();

  runApp(MyApp());
}

final ThemeData kIOSTheme = ThemeData(
    primarySwatch: Colors.orange,
    primaryColor: Colors.grey[100],
    primaryColorBrightness: Brightness.light);

final ThemeData kDefault = ThemeData(
    primarySwatch: Colors.purple, accentColor: Colors.orangeAccent[400]);

final googleSignIn = GoogleSignIn();
final auth = FirebaseAuth.instance;
int msgNum = 0;

Future<Null> _verifyLogInState() async {
  GoogleSignInAccount user = googleSignIn.currentUser;
  if (user == null) {
    user = await googleSignIn.signInSilently();
  }
  if (user == null) {
    user = await googleSignIn.signIn();

    QuerySnapshot snapshot =
        await Firestore.instance.collection("users").getDocuments();

    for (DocumentSnapshot doc in snapshot.documents) {
      print(doc.documentID);
    }

    Firestore.instance
        .collection("users")
        .document(googleSignIn.currentUser.id)
        .setData({
      "userName": googleSignIn.currentUser.displayName,
      "userId": googleSignIn.currentUser.id,
      "userEmail": googleSignIn.currentUser.email
    });
  }
  if (await auth.currentUser() == null) {
    GoogleSignInAuthentication credentials =
        await googleSignIn.currentUser.authentication;
    await auth.signInWithCredential(GoogleAuthProvider.getCredential(
        idToken: credentials.idToken, accessToken: credentials.accessToken));
  }
}

_handleText(String text) async {
  await _verifyLogInState();
  _sendMessage(text: text);
}

_signOut() async {
  await googleSignIn.disconnect();
  _verifyLogInState();
}

void _sendMessage({String text, String imgUrl}) {
  Firestore.instance.collection("messages").document().setData({
    "createdAt": Timestamp.now(),
    "text": text,
    "imgUrl": imgUrl,
    "senderName": googleSignIn.currentUser.displayName,
    "senderPhotoUrl": googleSignIn.currentUser.photoUrl,
    "senderId": googleSignIn.currentUser.id,
  });
  msgNum++;
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "chat_app",
      debugShowCheckedModeBanner: false,
      theme: Theme.of(context).platform == TargetPlatform.iOS
          ? kIOSTheme
          : kDefault,
      home: ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      top: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text("Chat App"),
          centerTitle: true,
          actions: <Widget>[
            IconButton(
              icon: Icon(Icons.menu),
              onPressed: _signOut,
            )
          ],
          elevation:
              Theme.of(context).platform == TargetPlatform.iOS ? 0.0 : 4.0,
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: StreamBuilder(
                stream: Firestore.instance
                    .collection("messages")
                    .orderBy('createdAt', descending: false)
                    .snapshots(),
                builder: (context, snapdhot) {
                  switch (snapdhot.connectionState) {
                    case ConnectionState.none:
                    case ConnectionState.waiting:
                      return Center(
                        child: CircularProgressIndicator(),
                      );
                    default:
                      return ListView.builder(
                          reverse: true,
                          itemCount: snapdhot.data.documents.length,
                          itemBuilder: (context, index) {
                            List r = snapdhot.data.documents.reversed.toList();
                            return ChatMessage(r[index].data);
                          });
                  }
                },
              ),
            ),
            Divider(
              height: 1.0,
            ),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
              ),
              child: TextComposer(),
            )
          ],
        ),
      ),
    );
  }
}

class TextComposer extends StatefulWidget {
  @override
  _TextComposerState createState() => _TextComposerState();
}

class _TextComposerState extends State<TextComposer> {
  final _textController = TextEditingController();
  bool _writing = false;

  void _resetTextFiled() {
    _textController.clear();
    setState(() {
      _writing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconTheme(
      data: IconThemeData(color: Theme.of(context).accentColor),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8.0),
        decoration: Theme.of(context).platform == TargetPlatform.iOS
            ? BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey[200])))
            : null,
        child: Row(
          children: <Widget>[
            Container(
              child: IconButton(
                icon: Icon(Icons.photo_camera),
                onPressed: () async {
                  File picture = await ImagePicker.pickImage(source: ImageSource.camera);
                  if(picture == null) return;
                  StorageUploadTask task = FirebaseStorage.instance.ref()
                      .child(googleSignIn.currentUser.id.toString()
                      + DateTime.now().millisecondsSinceEpoch.toString())
                      .putFile(picture);
                  StorageTaskSnapshot taskSnapshot = await task.onComplete;
                  String url = await taskSnapshot.ref.getDownloadURL();
                  _sendMessage(imgUrl: url);
                },
              ),
            ),
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: InputDecoration.collapsed(hintText: ""),
                onChanged: (text) {
                  setState(() {
                    _writing = text.length > 0;
                  });
                },
                onSubmitted: (text) {
                  _handleText(text);
                },
              ),
            ),
            Container(
              margin: EdgeInsets.symmetric(horizontal: 4.0),
              child: Theme.of(context).platform == TargetPlatform.iOS
                  ? CupertinoButton(
                      child: Text("Enviar"),
                      onPressed: _writing
                          ? () {
                              _handleText(_textController.text);
                              _resetTextFiled();
                            }
                          : null,
                    )
                  : IconButton(
                      icon: Icon(Icons.send),
                      onPressed: _writing
                          ? () {
                              _handleText(_textController.text);
                              _resetTextFiled();
                            }
                          : null,
                    ),
            )
          ],
        ),
      ),
    );
  }
}

class ChatMessage extends StatelessWidget {
  final Map<String, dynamic> data;

  ChatMessage(this.data);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
      child: Row(
        children: <Widget>[
          data["senderId"] != googleSignIn.currentUser.id
              ? Container(
                  margin: EdgeInsets.only(right: 16.0),
                  child: CircleAvatar(
                    backgroundImage:
                        data["senderId"] != googleSignIn.currentUser.id
                            ? NetworkImage(data["senderPhotoUrl"])
                            : null,
                  ),
                )
              : Container(),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  data["senderId"] != googleSignIn.currentUser.id
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.end,
              children: <Widget>[
                data["senderId"] != googleSignIn.currentUser.id
                    ? Text(data["senderName"],
                        style: TextStyle(fontSize: 10.0, color: Colors.grey))
                    : Text(""),
                Container(
                  margin: const EdgeInsets.only(top: 5.0),
                  child: data["imgUrl"] != null
                      ? Image.network(data["imgUrl"], width: 250.0)
                      : Text(data["text"]),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}

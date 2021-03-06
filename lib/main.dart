import 'package:flutter/material.dart';
import 'message.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:async';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:math';
import 'dart:io';

final googleSignIn = new GoogleSignIn();
final analytics = new FirebaseAnalytics();
final auth = FirebaseAuth.instance;
void main() {
  runApp(
    new FriendlychatApp()
  );
}

final ThemeData kIOSTheme = new ThemeData(
  primaryColor: Colors.grey[100],
  primaryColorBrightness: Brightness.light,
  primarySwatch: Colors.orange,
);
final ThemeData kDefaultTheme = new ThemeData(
  primarySwatch: Colors.purple,
  accentColor: Colors.orangeAccent[400],
);
class FriendlychatApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
      // TODO: implement build
      return new MaterialApp(
        title: "Friendlyhat",
        home: new ChatScreen(),
        theme: defaultTargetPlatform == TargetPlatform.iOS? kIOSTheme: kDefaultTheme,
      );
    }
}

class ChatScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return new ChatScreenState();
  }
}

class ChatScreenState extends State<ChatScreen> {
  // text field 와 연계하여, 매 텍스트 업데이트 마다
  // 업데이트 된 텍스트와 선택된 텍스트를 조정함. 초기값도 설정 가능
  final TextEditingController _textController = new TextEditingController();

  // 채팅 메시지 표기를 위한 부분
  bool _isComposing = false;

  // firebase 에서 메시지 가져오기
  final reference = FirebaseDatabase.instance.reference().child('messages');
  // 커스텀
  final _focusNode = new FocusNode();
  @override
  Widget build (BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text("Friendlychat"),
        elevation: 
          Theme.of(context).platform == TargetPlatform.iOS ? 0.0 : 4.0,
      ),
      // 위젯 아이템들을 수직으로 배열
      // 채팅 내용/구분자/최하단에 채팅 인풋 필드
      body: new Container(
        decoration: Theme.of(context).platform == TargetPlatform.iOS ? 
          new BoxDecoration(
            border: new Border(
              top: new BorderSide(color: Colors.grey[200]),
            )
          ): null,
        child: new Column(children: <Widget>[
          // 채팅 내용 부분
          new Flexible(
            child: new FirebaseAnimatedList(
              query: reference,
              sort: (a, b) => b.key.compareTo(a.key),
              padding: new EdgeInsets.all(8.0),
              reverse: true,
              itemBuilder: (_, DataSnapshot snapshot, Animation<double> animation, int idx){
                return new ChatMessage(
                  snapshot: snapshot,
                  animation: animation,
                );
              },  
            )
          ),
          new Divider(height: 1.0),
          // 채팅 입력 부분
          new Container(
            decoration: new BoxDecoration(
              color: Theme.of(context).cardColor,
            ),
            child: _buildTextComposer(),
          )
        ],)
      )
    );
  }

  Widget _buildTextComposer() {
    // 새로운 위젯을 생성하되 8.0 dp 마진을 사용
    return new IconTheme(
      data: new IconThemeData(color: Theme.of(context).accentColor),
      child: new Container(
        margin: const EdgeInsets.symmetric(horizontal: 8.0),
        // 같은 열에 텍스트 필드와 send 버튼을 위치시킨다.
        child: new Row(
          // 한 row에 들어갈 widget들을 배열로 정의 한다.
          children: <Widget>[
            // 다른 widget이 쓰고 남은 크기를 재사용 하도록 Flexible 위젯으로 만든다
            new Container (
              margin: new EdgeInsets.symmetric(horizontal: 4.0),
              child: new IconButton(
                icon: new Icon(Icons.photo_camera),
                onPressed: _handlePhoto, 
              )
            ),
            new Flexible(
              child: new TextField(
                controller: _textController, // text 변화 받아 들일 컨트롤러
                onSubmitted: _isComposing? _handleSubmitted: null, // 엔터/전송 했을 때 처리할 메소드
                decoration: new InputDecoration.collapsed( hintText: "Send a message"),
                focusNode: _focusNode,
                onChanged: _handleChange,
              ),
            ),
            // 아이콘 이미지에 맞는 크기를 갖도록 Container 사용 
            new Container(
              margin: new EdgeInsets.symmetric(horizontal: 4.0),
              child: Theme.of(context).platform == TargetPlatform.iOS ?
              new CupertinoButton(
                child: new Text("Send"),
                onPressed: _isComposing ? () => _handleSubmitted(_textController.text)
                            : null,
              ):
              new IconButton(
                icon: new Icon(Icons.send),
                onPressed: _isComposing ? () => _handleSubmitted(_textController.text)
                            : null,
              )
            )
          ]
        )
      )
    );
  }
  void _handlePhoto() async {
    await _ensureLoggedIn();
    File imageFile = await ImagePicker.pickImage(
      source: ImageSource.gallery,
    );
    int random = new Random().nextInt(100000);
    StorageReference ref = FirebaseStorage.instance.ref().child("image_$random.jpg");
    StorageUploadTask uploadTask = ref.putFile(imageFile);
    String downloadUrl = await (await uploadTask.onComplete).ref.getDownloadURL();
    _sendMessage(imageUrl: downloadUrl);
  }
  void _handleChange(String text) {
    setState(() {
      _isComposing = text.length > 0;
    });
  }
  void _handleSubmitted(String text) async {
    _textController.clear();
    setState(() {
          _isComposing = false;
        });
    FocusScope.of(context).requestFocus(_focusNode);
    await _ensureLoggedIn();
    _sendMessage(text: text);
    // 메시지 리스트에 추가할 새로운 메시지 위젯 생성
  }
  void _sendMessage({ String text, String imageUrl }) {
    reference.push().set({
      'text': text,
      'imageUrl': imageUrl,
      'senderName': googleSignIn.currentUser.displayName,
      'senderPhotoUrl': googleSignIn.currentUser.photoUrl,
    });
    analytics.logEvent(name: 'send_message');
  }

  // 구글 로그인
  Future<Null> _ensureLoggedIn() async {
    GoogleSignInAccount user = googleSignIn.currentUser;
    if (user == null) {
      user = await googleSignIn.signInSilently();
    }
    if (user == null) {
      await googleSignIn.signIn();
      analytics.logLogin();
    } 

    if (await auth.currentUser() == null) {
      GoogleSignInAuthentication credentials =
        await googleSignIn.currentUser.authentication;
      await auth.signInWithGoogle(
        idToken: credentials.idToken,
        accessToken: credentials.accessToken,
      );
    }
  }
}
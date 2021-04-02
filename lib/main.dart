import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class Item {
  Uint8List data;
  String contentType;
  String name;
}

int newLineN = "\n".codeUnitAt(0);
int newLineR = "\r".codeUnitAt(0);
int tabChar = "\t".codeUnitAt(0);
int spaceChar = " ".codeUnitAt(0);

List<int> lastLines(List<int> buf, int n) {
  List<int> out = [];
  for (int i = buf.length - 1; i >= 0; i--) {
    int c = buf[i];
    out.add(c);

    if (c == newLineN || c == newLineR) {
      if (n-- <= 0) {
        break;
      }
    }
  }
  return out.reversed.toList();
}

List<int> addPreviousLinesToEnd(int n, List<List<int>> out, List<int> current) {
  if (out.length > 0) {
    List<int> last = lastLines(out[out.length - 1], n);
    last.addAll(current);
    current = last;
  }
  return current;
}

void addChar(int c, List<int> current) {
  if (c == tabChar) {
    // Text is RichText and apparently it is not so rich to display tabs properly
    // so just replace tabs with 8 spaces, old school
    for (int k = 0; k < 8; k++) {
      current.add(spaceChar);
    }
  } else {
    current.add(c);
  }
}

List<String> getBufferData(List<int> bytes, int nBytesSplit) {
  List<List<int>> out = [];

  int left = nBytesSplit;
  List<int> current = [];

  for (int i = 0; i < bytes.length; i++) {
    int c = bytes[i];
    if (left > 0) {
      addChar(c, current);
      left--;
    } else {
      // split to closest new line
      int j = i;
      for (; j < bytes.length; j++) {
        int nextC = bytes[j];
        addChar(nextC, current);

        if (nextC == newLineN || nextC == newLineR) {
          break;
        }
      }
      i = j;

      // make sure each page has few lines from the previous page
      current = addPreviousLinesToEnd(5, out, current);

      out.add(current);
      current = new List();
      left = nBytesSplit;
    }
  }
  if (current.length > 0) {
    current = addPreviousLinesToEnd(5, out, current);

    out.add(current);
  }

  List<String> transformed = new List();
  out.forEach((f) {
    transformed.add(new String.fromCharCodes(f));
  });
  return transformed;
}

Future<List<String>> getFileData(String path, int nBytesSplit) async {
  return await rootBundle.load(path).then((b) {
    return getBufferData(b.buffer.asUint8List(), nBytesSplit);
  });
}

Future<Directory> getDirectory() async {
  var directory = await getApplicationDocumentsDirectory();
  var path = directory.path;
  directory = new Directory('$path/down');
  directory.createSync(recursive: true);
  return directory;
}

Future<File> download(Uri url, String name) async {
  final directory = await getDirectory();
  var path = directory.path;
  return http.get(url).then((response) {
    return new File('$path/$name').writeAsBytes(response.bodyBytes);
  });
}

void main() => runApp(TextyApp());

class TextLine extends StatelessWidget {
  final String text;
  final FontWeight fontWeight;
  final double size;

  TextLine(this.text, this.fontWeight, this.size);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: new TextStyle(
        fontFamily: "terminus",
        fontSize: this.size,
        fontWeight: fontWeight,
      ),
    );
  }
}

class Loading extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new Scaffold(
        body: Center(child: TextLine("loading...", FontWeight.bold, 18)));
  }
}

class Error extends StatelessWidget {
  Error({Key key, @required this.body, @required this.title}) : super(key: key);

  String body;
  String title;

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
        body: Center(
            child: AlertDialog(
                title: new Text(title),
                content: new Text(body),
                actions: <Widget>[
          new TextButton(
            child: new Text("Close"),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ])));
  }
}

class TextyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      title: 'Texy',
      home: new TextyPage(),
    );
  }
}

class TextyPage extends StatefulWidget {
  TextyPage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _TextyPageState createState() => new _TextyPageState();
}

class _TextyPageState extends State<TextyPage> {
  List<FileSystemEntity> downloaded;

  Future<List<FileSystemEntity>> listFiles() async {
    final directory = await getDirectory();
    Stream<FileSystemEntity> files =
        await directory.list(recursive: false, followLinks: false);
    List<FileSystemEntity> f = [];
    await files.forEach((e) {
      f.add(e);
    });
    f.sort((a, b) {
      return a.path.compareTo(b.path);
    });
    return f;
  }

  List<int> loadFile(FileSystemEntity f) {
    return File(f.path).readAsBytesSync();
  }

  Future deleteFile(FileSystemEntity f) async {
    f.deleteSync(recursive: false);
    return listFiles().then((files) {
      setState(() {
        downloaded = files;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    listFiles().then((f) {
      setState(() {
        downloaded = f;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (downloaded == null) {
      return Loading();
    }

    return new Scaffold(
      floatingActionButton: ButtonBar(
          mainAxisSize: MainAxisSize.max,
          alignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            new TextButton(
              child: TextLine("download", FontWeight.bold, 14),
              onPressed: () async {
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => new SettingsPage()));
                return listFiles().then((files) {
                  setState(() {
                    downloaded = files;
                  });
                });
              },
            ),
          ]),
      body: ListView.builder(
        itemBuilder: (BuildContext context, int index) {
          var f = downloaded[index];
          var name = getName(f);
          return ListTile(
              title: TextLine(name, FontWeight.bold, 18),
              onLongPress: () {
                _showDeleteDialog(f);
              },
              onTap: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => new BookPage(item: loadFile(f))));
              });
        },
        itemCount: downloaded.length,
      ),
    );
  }

  String getName(FileSystemEntity f) {
    return f.path.replaceAll(f.parent.path + "/", "").replaceAll("@", " ") +
        " " +
        (f.statSync().size / 1024).toStringAsFixed(1) +
        "kb";
  }

  void _showDeleteDialog(FileSystemEntity f) {
    // deleteFile(f);
    var name = getName(f);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: TextLine("Are you sure?", FontWeight.bold, 18),
          content:
              TextLine("you want to delete " + name, FontWeight.normal, 14),
          actions: <Widget>[
            new FlatButton(
              child: TextLine("Delete", FontWeight.bold, 16),
              textColor: Colors.red,
              onPressed: () {
                Navigator.of(context).pop();
                deleteFile(f);
              },
            ),
            new TextButton(
              child: TextLine("Cancel", FontWeight.bold, 16),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}

class BookPage extends StatefulWidget {
  final List<int> item;

  BookPage({Key key, this.item}) : super(key: key);

  @override
  BookState createState() => BookState(item);
}

class BookState extends State<BookPage> {
  List<String> book;
  final List<int> item;
  int currentPage = 0;
  double fontSize = 18;
  bool fitBox = false;
  bool showSpeedDial = false;
  ScrollController _scrollController;

  BookState(this.item);

  @override
  void initState() {
    super.initState();
    _scrollController = new ScrollController();
    book = getBufferData(item, 5000);
  }

  @override
  Widget build(BuildContext context) {
    if (book == null || book.length == 0) {
      return Loading();
    }

    var padding = EdgeInsets.all(0.0);

    var textLine = TextLine(book[currentPage], FontWeight.normal, fontSize);
    var fittedText = new FittedBox(fit: BoxFit.fitWidth, child: textLine);
    var settings = <Widget>[
      new IconButton(
          onPressed: () {
            setState(() {
              if (fontSize > 1) {
                fontSize--;
              }
            });
          },
          padding: padding,
          icon: TextLine("a", FontWeight.bold, fontSize - 4)),
      new IconButton(
          onPressed: () {
            setState(() {
              fontSize++;
            });
          },
          padding: padding,
          icon: TextLine("A", FontWeight.bold, fontSize - 4)),
      new IconButton(
          onPressed: () {
            setState(() {
              fitBox = !fitBox;
            });
          },
          padding: padding,
          icon: TextLine(
              fitBox ? "fit" : "un-fit", FontWeight.bold, fontSize - 4)),
      new IconButton(
          onPressed: () {
            // when pressed we will open menu to add notes
            // for now just do nothing
            setState(() {
              showSpeedDial = !showSpeedDial;
            });
          },
          padding: EdgeInsets.all(2.0),
          iconSize: 18,
          icon: TextLine("x", FontWeight.bold, fontSize)),
    ];

    var buttons = <Widget>[
      new IconButton(
          onPressed: () {
            setState(() {
              if (currentPage > 0) {
                currentPage--;
              }
            });
            _scrollController
                .jumpTo(_scrollController.position.maxScrollExtent);
          },
          padding: padding,
          icon: TextLine("<", FontWeight.bold, fontSize - 4)),
      new IconButton(
          onPressed: () {
            setState(() {
              showSpeedDial = !showSpeedDial;
            });
          },
          padding: padding,
          iconSize: 18,
          icon: TextLine(
              (currentPage + 1).toString() + "/" + book.length.toString(),
              FontWeight.bold,
              fontSize - 4)),
      new IconButton(
          onPressed: () {
            setState(() {
              currentPage = (currentPage + 1) % book.length;
            });
            _scrollController.jumpTo(0);
          },
          padding: padding,
          icon: TextLine(">", FontWeight.bold, fontSize - 4)),
    ];

    return new Scaffold(
      floatingActionButton: showSpeedDial
          ? Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.from(settings))
          : Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.from(buttons)),
      body: new SingleChildScrollView(
        controller: _scrollController,
        child: new SafeArea(
          child: new Container(
            child: fitBox ? textLine : fittedText,
            margin: const EdgeInsets.all(4.0),
            padding: const EdgeInsets.all(4.0),
          ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  SettingsPage({Key key, downloading: false}) : super(key: key);

  @override
  SettingsState createState() => SettingsState();
}

class SettingsState extends State<SettingsPage> {
  String name;
  String url;
  bool downloading;
  @override
  void initState() {
    name = "";
    url = "";
    downloading = false;
  }

  @override
  Widget build(BuildContext context) {
    if (downloading) {
      return Loading();
    }
    return new Scaffold(
      body: ListView(children: <Widget>[
        ListTile(
            title: TextFormField(
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            prefixIcon: TextLine("Name:", FontWeight.normal, 16),
          ),
          initialValue: "",
          onChanged: (input) {
            setState(() {
              name = input.replaceAll(new RegExp(r'[^\w+.]+'), "_");
            });
          },
        )),
        ListTile(
            title: TextFormField(
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            prefixIcon: TextLine("URL:", FontWeight.normal, 16),
          ),
          initialValue: "",
          onChanged: (input) {
            setState(() {
              url = input;
            });
          },
        )),
        ListTile(
            title: TextButton(
          child: TextLine("go", FontWeight.bold, 18),
          onPressed: () {
            if (url != null && name != null && url != "" && name != "") {
              try {
                var uri = Uri.parse(url);
                setState(() {
                  downloading = true;
                });
                download(uri, name)
                    .then((f) => {
                      Navigator.pop(context, f)
                    })
                    .catchError((err) {
                      setState(() {
                        downloading = false;
                      });
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              new Error(title: "error", body: err.toString())));
                });
              } catch (err) {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            new Error(title: "error", body: err.toString())));
              }
            } else {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => new Error(
                          title: "error",
                          body: "both url and name must be set")));
            }
          },
        )),
      ]),
    );
  }
}

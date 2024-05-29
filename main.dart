import 'dart:convert';
import 'dart:io';

const kPort = 3333;
const kAddress = '0.0.0.0';

/// Program start. Defaults to running the server, but if "client"
/// is provided as a commandline argument, it will start a client.
void main(List<String> arguments) async {
  final isClient = arguments.contains("client");

  if (isClient) {
    await runClient();
  } else {
    await runServer();
  }
}

const kMessageSeparator = '\n';

/// We have to manually handle incoming messages, because the socket only sees
/// packets, and doesn't conceptualize individual "messages"; we could receive
/// half of a "message" and next receive the 2nd half plus another whole message.
/// This class could be altered to handle our data in different formats, e.g.,
/// JSON or some sort of compression.
class DataParser {
  String _inProgress = '';

  /// Takes a String message, appends the separator and encodes it.
  static List<int> encode(String message) {
    return utf8.encode('$message$kMessageSeparator');
  }

  List<String> pushData(List<int> rawData) {
    _inProgress += utf8.decode(rawData);

    final completeMessages = <String>[];

    var index = _inProgress.indexOf(kMessageSeparator);
    while (index >= 0) {
      final message = _inProgress.substring(0, index + 1).trim();
      completeMessages.add(message);
      _inProgress = _inProgress.substring(index + 1);
      if (_inProgress.isEmpty) {
        break;
      }
      index = _inProgress.indexOf(kMessageSeparator);
    }

    return completeMessages;
  }
}

/// Starts a socket server which will accept connections and echo messages
Future<void> runServer() async {
  // open server, bound to address/port
  final server = await ServerSocket.bind(kAddress, kPort);

  // handle server port close
  onServerClose() {
    print('SERVER CLOSED');
  }

  // handle connecting clients
  List<Socket> clients = [];

  // Sends a message to all connected clients,
  // allowing for excluding the "sender"
  sendMessageToClients(String message, [Socket? exceptSender]) {
    final asData = DataParser.encode(message);
    for (final client in clients) {
      if (client == exceptSender) {
        continue;
      }
      client.add(asData);
    }
  }

  onClientConnect(Socket clientSocket) {
    final parser = DataParser();
    print('CLIENT JOINED ${clientSocket.hashCode}');

    clients.add(clientSocket);

    clientSocket.listen((List<int> data) {
      final messages = parser.pushData(data);
      for (final message in messages) {
        final withSender = '[${clientSocket.hashCode}]: $message';
        print(withSender);
        sendMessageToClients(withSender, clientSocket);
      }
    }, onDone: () {
      clients.remove(clientSocket);
      print('CLIENT LEFT ${clientSocket.hashCode}');
      sendMessageToClients(
          "[SERVER] client ${clientSocket.hashCode} has left.");
    });

    // tell the client "hello"
    clientSocket.add(DataParser.encode(
        '[SERVER] Hello, your id is ${clientSocket.hashCode}.'));

    // tell all of the other clients that someone has joined
    sendMessageToClients(
        "[SERVER] client ${clientSocket.hashCode} has joined.", clientSocket);
  }

  // handle connections and close
  server.listen(onClientConnect, onDone: onServerClose);

  print('SERVER STARTED $kAddress:$kPort');
}

/// Starts a client socket which will connect to the address/port and
/// send/receive messages
Future<void> runClient() async {
  final client = await Socket.connect(kAddress, kPort);
  var open = true;
  print("CLIENT STARTED $kAddress:$kPort");
  final parser = DataParser();

  // on close connection
  onClose() {
    open = false;
  }

  // listen to incoming messages
  onMessage(List<int> data) {
    final messages = parser.pushData(data);
    for (final message in messages) {
      print(message);
    }
  }

  client.listen(onMessage, onDone: onClose);
  while (open) {
    print('SENDING MESSAGE');
    client.add(DataParser.encode('Hello, world!'));
    await Future.delayed(Duration(seconds: 2));
  }
}

import 'dart:io';
import 'dart:isolate';
import 'package:pub_sub/isolate.dart' as pub_sub;
import 'package:pub_sub/pub_sub.dart' as pub_sub;

main() async {
  // Easily bring up a server.
  var adapter = new pub_sub.IsolateAdapter();
  var server = new pub_sub.Server([adapter]);

  // You then need to create a client that will connect to the adapter.
  // Each isolate in your application should contain a client.
  for (int i = 0; i < Platform.numberOfProcessors - 1; i++) {
    server.registerClient(new pub_sub.ClientInfo('client$i'));
  }

  // Start the server.
  server.start();

  // Next, let's start isolates that interact with the server.
  //
  // Fortunately, we can send SendPorts over Isolates, so this is no hassle.
  for (int i = 0; i < Platform.numberOfProcessors - 1; i++)
    Isolate.spawn(isolateMain, [i, adapter.receivePort.sendPort]);

  // It's possible that you're running your application in the server isolate as well:
  isolateMain([0, adapter.receivePort.sendPort]);
}

void isolateMain(List args) {
  var client =
      new pub_sub.IsolateClient('client${args[0]}', args[1] as SendPort);

  // The client will connect automatically. In the meantime, we can start subscribing to events.
  client.subscribe('user::logged_in').then((sub) {
    // The `ClientSubscription` class extends `Stream`. Hooray for asynchrony!
    sub.listen((msg) {
      print('Logged in: $msg');
    });
  });
}

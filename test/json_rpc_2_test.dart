import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:pub_sub/pub_sub.dart';
import 'package:pub_sub/json_rpc_2.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

main() {
  ServerSocket serverSocket;
  Server server;
  Client client1, client2, client3;
  JsonRpc2Adapter adapter;

  setUp(() async {
    serverSocket = await ServerSocket.bind(InternetAddress.LOOPBACK_IP_V4, 0);

    adapter = new JsonRpc2Adapter(
        serverSocket.map<StreamChannel<String>>(streamSocket));

    var socket1 =
        await Socket.connect(InternetAddress.LOOPBACK_IP_V4, serverSocket.port);
    var socket2 =
        await Socket.connect(InternetAddress.LOOPBACK_IP_V4, serverSocket.port);
    var socket3 =
        await Socket.connect(InternetAddress.LOOPBACK_IP_V4, serverSocket.port);

    client1 =
        new JsonRpc2Client('json_rpc_2_test::secret', streamSocket(socket1));
    client2 =
        new JsonRpc2Client('json_rpc_2_test::secret2', streamSocket(socket2));
    client3 =
        new JsonRpc2Client('json_rpc_2_test::secret3', streamSocket(socket3));

    server = new Server([adapter])
      ..registerClient(const ClientInfo('json_rpc_2_test::secret'))
      ..registerClient(const ClientInfo('json_rpc_2_test::secret2'))
      ..registerClient(const ClientInfo('json_rpc_2_test::secret3'))
      ..registerClient(
          const ClientInfo('json_rpc_2_test::no_publish', canPublish: false))
      ..registerClient(
          const ClientInfo('json_rpc_2_test::no_subscribe', canSubscribe: false))
      ..start();

    var sub = await client3.subscribe('foo');
    sub.listen((data) {
      print('Client3 caught foo: $data');
    });
  });

  tearDown(() {
    Future.wait(
        [server.close(), client1.close(), client2.close(), client3.close()]);
  });

  test('subscribers receive published events', () async {
    var sub = await client2.subscribe('foo');
    await client1.publish('foo', 'bar');
    expect(await sub.first, 'bar');
  });

  test('subscribers are not sent their own events', () async {
    var sub = await client1.subscribe('foo');
    await client1.publish('foo',
        '<this should never be sent to client1, because client1 sent it.>');
    await sub.unsubscribe();
    expect(await sub.isEmpty, isTrue);
  });

  test('can unsubscribe', () async {
    var sub = await client2.subscribe('foo');
    await client1.publish('foo', 'bar');
    await sub.unsubscribe();
    await client1.publish('foo', '<client2 will not catch this!>');
    expect(await sub.length, 1);
  });

  group('json_rpc_2_server', () {
    test('reject unknown client id', () async {
      try {
        var sock = await Socket.connect(
            InternetAddress.LOOPBACK_IP_V4, serverSocket.port);
        var client =
            new JsonRpc2Client('json_rpc_2_test::invalid', streamSocket(sock));
        await client.publish('foo', 'bar');
        throw 'Invalid client ID\'s should throw an error, but they do not.';
      } on PubSubException catch (e) {
        print('Expected exception was thrown: ${e.message}');
      }
    });

    test('reject unprivileged publish', () async {
      try {
        var sock = await Socket.connect(
            InternetAddress.LOOPBACK_IP_V4, serverSocket.port);
        var client =
            new JsonRpc2Client('json_rpc_2_test::no_publish', streamSocket(sock));
        await client.publish('foo', 'bar');
        throw 'Unprivileged publishes should throw an error, but they do not.';
      } on PubSubException catch (e) {
        print('Expected exception was thrown: ${e.message}');
      }
    });

    test('reject unprivileged subscribe', () async {
      try {
        var sock = await Socket.connect(
            InternetAddress.LOOPBACK_IP_V4, serverSocket.port);
        var client = new JsonRpc2Client(
            'json_rpc_2_test::no_subscribe', streamSocket(sock));
        await client.subscribe('foo');
        throw 'Unprivileged subscribes should throw an error, but they do not.';
      } on PubSubException catch (e) {
        print('Expected exception was thrown: ${e.message}');
      }
    });
  });
}

StreamChannel<String> streamSocket(Socket socket) {
  var channel = new _SocketStreamChannel(socket);
  return channel.transform(new StreamChannelTransformer.fromCodec(UTF8));
}

class _SocketStreamChannel extends StreamChannelMixin<List<int>> {
  _SocketSink _sink;
  final Socket socket;

  _SocketStreamChannel(this.socket);

  @override
  StreamSink<List<int>> get sink => _sink ??= new _SocketSink(socket);

  @override
  Stream<List<int>> get stream => socket;
}

class _SocketSink extends StreamSink<List<int>> {
  final Socket socket;

  _SocketSink(this.socket);

  @override
  void add(List<int> event) {
    socket.add(event);
  }

  @override
  void addError(Object error, [StackTrace stackTrace]) {
    Zone.current.errorCallback(error, stackTrace);
  }

  @override
  Future addStream(Stream<List<int>> stream) {
    return socket.addStream(stream);
  }

  @override
  Future close() {
    return socket.close();
  }

  @override
  Future get done => socket.done;
}
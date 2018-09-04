import 'dart:async';
import 'dart:isolate';
import 'package:uuid/uuid.dart';
import '../../pub_sub.dart';

/// A [Adapter] implementation that communicates via [SendPort]s and [ReceivePort]s.
class IsolateAdapter extends Adapter {
  final Map<String, SendPort> _clients = {};
  final StreamController<PublishRequest> _onPublish =
      new StreamController<PublishRequest>();
  final StreamController<SubscriptionRequest> _onSubscribe =
      new StreamController<SubscriptionRequest>();
  final StreamController<UnsubscriptionRequest> _onUnsubscribe =
      new StreamController<UnsubscriptionRequest>();
  final Uuid _uuid = new Uuid();

  /// A [ReceivePort] on which to listen for incoming data.
  final ReceivePort receivePort = new ReceivePort();
  @override
  Stream<PublishRequest> get onPublish => _onPublish.stream;

  @override
  Stream<SubscriptionRequest> get onSubscribe => _onSubscribe.stream;

  @override
  Stream<UnsubscriptionRequest> get onUnsubscribe => _onUnsubscribe.stream;

  @override
  Future close() {
    receivePort.close();
    _clients.clear();
    _onPublish.close();
    _onSubscribe.close();
    _onUnsubscribe.close();
    return new Future.value();
  }

  @override
  void start() {
    receivePort.listen((data) {
      if (data is SendPort) {
        var id = _uuid.v4() as String;
        _clients[id] = data;
        data.send({'status': true, 'id': id});
      } else if (data is Map &&
          data['id'] is String &&
          data['request_id'] is String &&
          data['method'] is String &&
          data['params'] is Map) {
        String id = data['id'],
            requestId = data['request_id'],
            method = data['method'];
        Map params = data['params'];
        var sp = _clients[id];

        if (sp == null) {
          // There's nobody to respond to, so don't send anything to anyone. Oops.
        } else if (method == 'publish') {
          if (params['client_id'] is String &&
              params['event_name'] is String &&
              params.containsKey('value')) {
            String clientId = params['client_id'],
                eventName = params['event_name'];
            var value = params['value'];
            var rq = new _IsolatePublishRequestImpl(
                requestId, clientId, eventName, value, sp);
            _onPublish.add(rq);
          } else {
            sp.send({
              'status': false,
              'request_id': requestId,
              'error_message': 'Expected client_id, event_name, and value.'
            });
          }
        } else if (method == 'subscribe') {
          if (params['client_id'] is String && params['event_name'] is String) {
            String clientId = params['client_id'],
                eventName = params['event_name'];
            var rq = new _IsolateSubscriptionRequestImpl(
                clientId, eventName, sp, requestId, _uuid);
            _onSubscribe.add(rq);
          } else {
            sp.send({
              'status': false,
              'request_id': requestId,
              'error_message': 'Expected client_id, and event_name.'
            });
          }
        } else if (method == 'unsubscribe') {
          if (params['client_id'] is String &&
              params['subscription_id'] is String) {
            String clientId = params['client_id'],
                subscriptionId = params['subscription_id'];
            var rq = new _IsolateUnsubscriptionRequestImpl(
                clientId, subscriptionId, sp, requestId);
            _onUnsubscribe.add(rq);
          } else {
            sp.send({
              'status': false,
              'request_id': requestId,
              'error_message': 'Expected client_id, and subscription_id.'
            });
          }
        } else {
          sp.send({
            'status': false,
            'request_id': requestId,
            'error_message':
                'Unrecognized method "$method". Or, you omitted id, request_id, method, or params.'
          });
        }
      }
    });
  }
}

class _IsolatePublishRequestImpl extends PublishRequest {
  @override
  final String clientId;

  @override
  final String eventName;

  @override
  final value;

  final SendPort sendPort;

  final String requestId;

  _IsolatePublishRequestImpl(
      this.requestId, this.clientId, this.eventName, this.value, this.sendPort);

  @override
  void accept(PublishResponse response) {
    sendPort.send({
      'status': true,
      'request_id': requestId,
      'result': {'listeners': response.listeners}
    });
  }

  @override
  void reject(String errorMessage) {
    sendPort.send({
      'status': false,
      'request_id': requestId,
      'error_message': errorMessage
    });
  }
}

class _IsolateSubscriptionRequestImpl extends SubscriptionRequest {
  @override
  final String clientId;

  @override
  final String eventName;

  final SendPort sendPort;

  final String requestId;

  final Uuid _uuid;

  _IsolateSubscriptionRequestImpl(
      this.clientId, this.eventName, this.sendPort, this.requestId, this._uuid);

  @override
  void reject(String errorMessage) {
    sendPort.send({
      'status': false,
      'request_id': requestId,
      'error_message': errorMessage
    });
  }

  @override
  FutureOr<Subscription> accept() {
    var id = _uuid.v4() as String;
    sendPort.send({
      'status': true,
      'request_id': requestId,
      'result': {'subscription_id': id}
    });
    return new _IsolateSubscriptionImpl(clientId, id, eventName, sendPort);
  }
}

class _IsolateSubscriptionImpl extends Subscription {
  @override
  final String clientId, id;

  final String eventName;

  final SendPort sendPort;

  _IsolateSubscriptionImpl(
      this.clientId, this.id, this.eventName, this.sendPort);

  @override
  void dispatch(event) {
    sendPort.send([eventName, event]);
  }
}

class _IsolateUnsubscriptionRequestImpl extends UnsubscriptionRequest {
  @override
  final String clientId;

  @override
  final String subscriptionId;

  final SendPort sendPort;

  final String requestId;

  _IsolateUnsubscriptionRequestImpl(
      this.clientId, this.subscriptionId, this.sendPort, this.requestId);

  @override
  void reject(String errorMessage) {
    sendPort.send({
      'status': false,
      'request_id': requestId,
      'error_message': errorMessage
    });
  }

  @override
  accept() {
    sendPort.send({'status': true, 'request_id': requestId, 'result': {}});
  }
}

// Copyright (c) 2013, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

/**
 * A preferences implementation. [PreferenceStore] is the abstract definition of
 * a preference store. [localStore] and [syncStore] are concrete implementations
 * backed by `chrome.storage.local` and 'chrome.storage.sync` respectively.
 *
 * [MapPreferencesStore] is an implementation backed by a [Map].
 */
library spark.preferences;

import 'dart:async';

import 'package:chrome_gen/chrome_app.dart' as chrome;

/**
 * A PreferenceStore backed by `chome.storage.local`.
 */
PreferenceStore localStore = new _ChromePreferenceStore(chrome.storage.local, 'local');

/**
 * A PreferenceStore backed by `chome.storage.sync`.
 */
PreferenceStore syncStore = new _ChromePreferenceStore(chrome.storage.sync, 'sync');

/**
 * A persistent preference mechanism.
 */
abstract class PreferenceStore {
  /**
   * Whether this preference store has any unwritten changes.
   */
  bool get isDirty;

  /**
   * Get the value for the given key. The value is returned as a [Future].
   */
  Future<String> getValue(String key);

  /**
   * Set the value for the given key. The returned [Future] has the same value
   * as [value] on success.
   */
  Future<String> setValue(String key, String value);

  /**
   * Flush any unsaved changes to this [PreferenceStore].
   */
  void flush();

  Stream<PreferenceEvent> get onPreferenceChange;
}

/**
 * A [PreferenceStore] implementation based on a [Map].
 */
class MapPreferencesStore implements PreferenceStore {
  Map _map = {};
  bool _dirty = false;
  StreamController<PreferenceEvent> _controller = new StreamController.broadcast();

  bool get isDirty => _dirty;

  Future<String> getValue(String key) => new Future.value(_map[key]);

  Future<String> setValue(String key, String value) {
    _dirty = true;
    _map[key] = value;
    _controller.add(new PreferenceEvent(this, key, value));
    return new Future.value(_map[key]);
  }

  void flush() {
    _dirty = false;
  }

  Stream<PreferenceEvent> get onPreferenceChange => _controller.stream;
}

/**
 * A [PreferenceStore] implementation based on `chrome.storage`.
 *
 * This preferences implementation will automatically flush any dirty changes
 * out to `chrome.storage` every 6 seconds. That frequency will ensure that we
 * do not exceed the rate limit imposed by `chrome.storage.sync`.
 */
class _ChromePreferenceStore implements PreferenceStore {
  Map _map = {};
  StreamController<PreferenceEvent> _controller = new StreamController.broadcast();
  chrome.StorageArea _storageArea;
  Timer _timer;

  _ChromePreferenceStore(this._storageArea, String name) {
    chrome.storage.onChanged.listen((chrome.StorageOnChangedEvent event) {
      if (event.areaName == name) {
        for (String key in event.changes.keys) {
          chrome.StorageChange change = event.changes[key];

          // We only understand strings.
          if (change.newValue is String || change.newValue == null) {
            _controller.add(new PreferenceEvent(this, key, change.newValue));
          }
        }
      }
    });
  }

  bool get isDirty => _map.isNotEmpty;

  /**
   * Get the value for the given key. The value is returned as a [Future].
   */
  Future<String> getValue(String key) {
    if (_map.containsKey(key)) {
      return new Future.value(_map[key]);
    } else {
      return _storageArea.get(key).then((Map<String, String> map) {
        return map == null ? null : map[key];
      });
    }
  }

  /**
   * Set the value for the given key. The returned [Future] has the same value
   * as [value] on success.
   */
  Future<String> setValue(String key, String value) {
    _map[key] = value;
    _controller.add(new PreferenceEvent(this, key, value));

    _startTimer();

    return new Future.value(_map[key]);
  }

  /**
   * Flush any unsaved changes to this [PreferenceStore].
   */
  void flush() {
    if (_map.isNotEmpty) {
      _storageArea.set(_map);
      _map.clear();
    }

    if (_timer != null) {
      _timer.cancel();
      _timer = null;
    }
  }

  Stream<PreferenceEvent> get onPreferenceChange => _controller.stream;

  void _startTimer() {
    if (_timer == null) {
      // Flush dirty preferences every 6 seconds.
      _timer = new Timer(new Duration(seconds: 6), flush);
    }
  }
}

/**
 * A event class for preference changes.
 */
class PreferenceEvent {
  final PreferenceStore store;
  final String key;
  final String value;

  PreferenceEvent(this.store, this.key, this.value);
}
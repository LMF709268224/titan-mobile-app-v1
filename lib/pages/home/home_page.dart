import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:titan_app/providers/version_provider.dart';
import 'package:titan_app/themes/colors.dart';
import 'package:titan_app/utils/system_utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../bean/bridge_mgr.dart';
import '../../l10n/generated/l10n.dart';
import '../../utils/utility.dart';
import '../../widgets/common_text_widget.dart';
import '../../widgets/loading_indicator.dart';
import '/ffi/titanedge_jcall.dart' as nativel2;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  final double kImageSize = 300.w;
  double money = 0.0;
  late VideoPlayerController _prepareController;
  late VideoPlayerController _runningController;
  late Future<void> _initializePrepareVideoPlayerFuture;
  late Future<void> _initializeRunningVideoPlayerFuture;

  Duration loopStart = const Duration(seconds: 3);
  Duration prepareStart = const Duration(seconds: 0);
  bool isDaemonRunning = false;
  bool isDaemonOnline = false;
  int daemonCounter = 0;
  bool isClickHandling = false;

  late Timer timer;
  bool isQuerying = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _prepareController =
        VideoPlayerController.asset('assets/videos/prepare.mp4');
    _runningController =
        VideoPlayerController.asset('assets/videos/running.mp4');
    _prepareController.setLooping(true);
    _runningController.setLooping(true);
    _initializePrepareVideoPlayerFuture = _prepareController.initialize();
    _initializeRunningVideoPlayerFuture = _runningController.initialize();

    timer = Timer.periodic(const Duration(seconds: 3), (Timer timer) {
      queryDaemonState();
    });

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      BridgeMgr().minerBridge.minerInfo.addListener("income", "today", () {
        setState(() {
          money = BridgeMgr().minerBridge.minerInfo.todayIncome();
        });
      });
    });

    _updateAnimation();
  }

  void _updateAnimation() {
    const Duration zero = Duration(seconds: 0);
    _runningController.seekTo(zero);
    _runningController.pause();
    _prepareController.seekTo(zero);
    _prepareController.pause();

    switch (isDaemonRunning) {
      case false:
        break;
      case true:
        if (isDaemonOnline) {
          _runningController.play();
        } else {
          _prepareController.play();
        }
        break;
    }
  }

  @override
  void dispose() {
    _prepareController.dispose();
    _runningController.dispose();
    timer.cancel();
    BridgeMgr().minerBridge.minerInfo.removeListener("income", "today");
    super.dispose();
  }

  double isVisible() {
    return !isDaemonRunning ? 0.0 : 1;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final String versionName =
        Provider.of<VersionProvider>(context, listen: false).localVersion;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Center(
        child: Stack(
          children: [
            Positioned(
              top: 144.h,
              left: (MediaQuery.of(context).size.width - kImageSize - 40.w) /
                  2, //40 buffer
              child: SizedBox(
                width: kImageSize,
                height: kImageSize,
                child: _imageNode(context),
              ),
            ),
            Column(
              children: [
                SizedBox(
                  height: 137.h,
                ),
                _todayEarnings(context),
                // SizedBox(
                //   height: 20.h,
                // ),
                // _imageNode(context),
                SizedBox(
                  height: 220.h,
                ),
                Text(
                  S.of(context).current_device_ID,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFFAFAFA),
                  ),
                ),
                SizedBox(
                  height: 8.h,
                ),
                Text(
                  BridgeMgr().daemonBridge.daemonCfgs.id(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF909090),
                  ),
                ),
                SizedBox(
                  height: SystemUtils.isIOS ? 100.h : 120.h,
                ),
                _startButton(context),
                SizedBox(
                  height: 12.h,
                ),
                _earningInfoButton(context),
                SizedBox(
                  height: 32.h,
                ),
                CommonTextWidget(
                  versionName,
                  fontSize: FontSize.extraSmall,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> toMoneyDetailPage() async {
    if (!isDaemonRunning) {
      return;
    }

    String url =
        'https://test1.titannet.io/nodeidDetail?device_id=${BridgeMgr().daemonBridge.daemonCfgs.id()}';
    if (!await launchUrl(Uri.parse(url))) {
      throw Exception('Could not launch $url');
    }
  }

  Widget _todayEarnings(BuildContext context) {
    return Opacity(
        opacity: isVisible(),
        child: RichText(
          text: TextSpan(
            text: S.of(context).today_earnings,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontSize: 14.0.sp),
            children: [
              TextSpan(
                  text: ' ${money.toStringAsFixed(3)} ',
                  style: TextStyle(
                      color: AppDarkColors.themeColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 28.0.sp),
                  children: [
                    TextSpan(
                        text: BridgeMgr().minerBridge.minerInfo.tokenUnit(),
                        style: TextStyle(
                            color: AppDarkColors.titleColor, fontSize: 14.0.sp))
                  ])
            ],
          ),
        ));
  }

  Widget _imageNode(BuildContext context) {
    // if (!isDaemonRunning) {
    //   return Image.asset(
    //     "assets/images/mobile_node_stop.png",
    //     fit: BoxFit.contain,
    //   );
    // }
    if (!isDaemonRunning) {
      return _startPrepareNode(context);
    } else {
      return _startRunningNode(context);
    }
  }

  Widget _startPrepareNode(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: FutureBuilder(
          future: _initializePrepareVideoPlayerFuture,
          builder: (context, snapshot) {
            return Image.asset("assets/images/mobile_node_stop.png",
                fit: BoxFit.contain);
          }),
    );
  }

  Widget _startRunningNode(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: FutureBuilder(
          future: _initializeRunningVideoPlayerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              if (isDaemonOnline) {
                return AspectRatio(
                  aspectRatio: _runningController.value.aspectRatio * 1,
                  child: VideoPlayer(_runningController),
                );
              } else {
                return AspectRatio(
                  aspectRatio: _prepareController.value.aspectRatio * 1,
                  child: VideoPlayer(_prepareController),
                );
              }
            } else {
              return Image.asset("assets/images/mobile_node_stop.png",
                  fit: BoxFit.contain);
            }
          }),
    );
  }

  Widget _startButton(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        handleStartStopClick(context);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: (!isDaemonRunning)
            ? AppDarkColors.themeColor
            : const Color(0xff181818),
        minimumSize: Size(335.w, 48.h),
      ),
      child: Text(
        (!isDaemonRunning)
            ? S.of(context).start_earning_coins
            : S.of(context).stop_earning_coins,
        style: TextStyle(
            color: (!isDaemonRunning)
                ? AppDarkColors.backgroundColor
                : AppDarkColors.grayColor,
            fontSize: 18.sp),
      ),
    );
  }

  Widget _earningInfoButton(BuildContext context) {
    return Opacity(
        opacity: isVisible(),
        child: ElevatedButton(
          onPressed: toMoneyDetailPage,
          style: ButtonStyle(
            backgroundColor:
                MaterialStateProperty.all<Color>(Colors.transparent),
            shape: MaterialStateProperty.all<RoundedRectangleBorder>(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(85.0),
                side: const BorderSide(color: AppDarkColors.themeColor),
              ),
            ),
            minimumSize: MaterialStateProperty.all<Size>(Size(335.w, 48.h)),
            elevation: MaterialStateProperty.all<double>(5),
            overlayColor: MaterialStateProperty.all<Color>(
                Colors.lightBlueAccent.withOpacity(0.5)),
          ),
          child: Text(
            S.of(context).view_earnings_details,
            style: TextStyle(color: AppDarkColors.themeColor, fontSize: 18.sp),
          ),
        ));
  }

  Future<Map<String, dynamic>> startDaemon() async {
    var directory = await getApplicationDocumentsDirectory();
    var repoPath = path.join(directory.path, "titanl2");
    var repoDirectory = Directory(repoPath);
    if (!await repoDirectory.exists()) {
      await repoDirectory.create();
    }

    debugPrint("path $repoDirectory");

    Map<String, dynamic> startDaemonArgs = {
      'repoPath': repoPath,
      'logPath': path.join(directory.path, "edge.log"),
      'locatorURL': "https://test-locator.titannet.io:5000/rpc/v0"
    };

    String startDaemonArgsJSON = json.encode(startDaemonArgs);

    Map<String, dynamic> jsonCallArgs = {
      'method': 'startDaemon',
      'JSONParams': startDaemonArgsJSON,
    };

    var args = json.encode(jsonCallArgs);

    String jsonResult = "";
    int tryCall = 0;
    bool isOK = false;

    while (tryCall < 5) {
      jsonResult = await nativel2.L2APIs().jsonCall(args);
      if (!isJsonResultOK(jsonResult)) {
        // delay 1 seconds
        await Future.delayed(const Duration(seconds: 1));
        tryCall++;
        continue;
      }

      isOK = true;
      break;
    }

    if (!isOK) {
      return {"bool": false, "r": jsonResult};
    }

    // query y times
    tryCall = 0;
    isOK = false;
    while (tryCall < 5) {
      // delay 1 seconds
      await Future.delayed(const Duration(seconds: 1));
      jsonResult = await daemonState();
      if (!isJsonResultOK(jsonResult)) {
        tryCall++;
        continue;
      }

      isOK = true;
      break;
    }

    return {"bool": isOK, "r": jsonResult};
  }

  Future<Map<String, dynamic>> stopDaemon() async {
    Map<String, dynamic> stopDaemonArgs = {
      'method': 'stopDaemon',
      'JSONParams': "",
    };

    var args = json.encode(stopDaemonArgs);

    String jsonResult = "";
    int tryCall = 0;
    bool isOK = false;

    while (tryCall < 5) {
      jsonResult = await nativel2.L2APIs().jsonCall(args);
      if (!isJsonResultOK(jsonResult)) {
        // delay 1 seconds
        await Future.delayed(const Duration(seconds: 1));
        tryCall++;
        continue;
      }

      isOK = true;
      break;
    }

    if (!isOK) {
      return {"bool": false, "r": jsonResult};
    }

    // query y times
    tryCall = 0;
    isOK = false;
    while (tryCall < 5) {
      // delay 1 seconds
      await Future.delayed(const Duration(seconds: 1));
      jsonResult = await daemonState();

      // if stop successfully, state call will failed
      if (isJsonResultOK(jsonResult)) {
        tryCall++;
        continue;
      }

      isOK = true;
      break;
    }

    return {"bool": isOK, "r": jsonResult};
  }

  Future<String> daemonState() async {
    Map<String, dynamic> jsonCallArgs = {
      'method': 'state',
      'JSONParams': "",
    };

    var args = json.encode(jsonCallArgs);
    var result = await nativel2.L2APIs().jsonCall(args);

    return result;
  }

  bool isJsonResultOK(String jsonString) {
    Map<String, dynamic> j = jsonDecode(jsonString);
    return j['code'] == 0;
  }

  void handleSignClick() async {
    var ret = await daemonSign();
    debugPrint('handleSignClick: $ret');
  }

  Future<String> daemonSign() async {
    var directory = await getApplicationDocumentsDirectory();
    var repoPath = path.join(directory.path, "titanl2");

    Map<String, dynamic> signReqArgs = {'repoPath': repoPath, 'hash': "abc"};

    var signReqArgsJSON = json.encode(signReqArgs);

    Map<String, dynamic> jsonCallArgs = {
      'method': 'sign',
      'JSONParams': signReqArgsJSON,
    };

    var args = json.encode(jsonCallArgs);

    var result = await nativel2.L2APIs().jsonCall(args);
    return result;
  }

  void queryDaemonState() async {
    if (isQuerying) {
      return;
    }

    // if is click by user, stop query
    if (isClickHandling) {
      return;
    }

    isQuerying = true;
    String result;

    result = await daemonState();

    debugPrint('~~~state call: $result');

    isQuerying = false;

    var jsonResult = jsonDecode(result);
    bool isOnline = false;
    bool isRunning = false;

    if (jsonResult["code"] == 0) {
      isRunning = true;
      final data = jsonDecode(jsonResult["data"]);
      bool online = data["online"];
      isOnline = online;

      if (BridgeMgr().daemonBridge.daemonCfgs.id() == "") {
        await BridgeMgr().daemonBridge.loadDaemonConfig();
        // update node info
        var cfg = BridgeMgr().daemonBridge.daemonCfgs;
        BridgeMgr().minerBridge.setNodeInfo(cfg.id(), cfg.areaID());
        // pull data from server
        BridgeMgr().minerBridge.pullInfo();
      }
    }

    if (isDaemonRunning == isRunning && isDaemonOnline == isOnline) {
      return;
    }

    // if it is offline, stop increase incoming
    if (!isOnline && isDaemonOnline) {
      BridgeMgr().minerBridge.minerInfo.clearIncomeIncr();
    }

    setState(() {
      isDaemonRunning = isRunning;
      isDaemonOnline = isOnline;
      _updateAnimation();
    });
  }

  void handleStartStopClick(BuildContext context) async {
    if (isClickHandling) {
      return;
    }

    isClickHandling = true;
    Map<String, dynamic> result;

    String action;
    final String indicatorMsg =
        isDaemonRunning ? S.of(context).stopping : S.of(context).starting;
    LoadingIndicator.show(context, message: indicatorMsg);

    if (isDaemonRunning) {
      result = await stopDaemon();
      action = "Stop daemon";
    } else {
      result = await startDaemon();
      action = "Start daemon";
    }

    if (context.mounted) {
      LoadingIndicator.hide(context);
    }

    isClickHandling = false;

    debugPrint('start/stop call, action:$action, result: $result');

    if (result["bool"]) {
      setState(() {
        isDaemonRunning = !isDaemonRunning;
        _updateAnimation();
      });
    } else {
      if (context.mounted) {
        String msg = result["r"];
        Indicators.showMessage(context, action, msg, null, null);
      }
    }
  }
}

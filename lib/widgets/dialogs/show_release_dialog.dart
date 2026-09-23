import 'dart:async';
import 'dart:io';
import 'package:iris/utils/file_size_convert.dart';
import 'package:iris/utils/platform.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:iris/app_shutdown.dart';
import 'package:iris/utils/get_latest_release.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/url.dart';

bool isPortable() {
  String resolvedExecutablePath = Platform.resolvedExecutable;
  String path = p.dirname(resolvedExecutablePath);
  String batFilePath = p.join(path, 'iris-updater.bat');
  return File(batFilePath).existsSync();
}

Future<void> showReleaseDialog(BuildContext context,
        {required Release release}) async =>
    await showDialog<void>(
      context: context,
      builder: (context) => ReleaseDialog(
        release: release,
      ),
    );

class ReleaseDialog extends HookWidget {
  const ReleaseDialog({super.key, required this.release});

  final Release release;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    final updateScriptIsExists = useState(false);

    useEffect(() {
      if (isWindows) {
        updateScriptIsExists.value = isPortable();
      }
      return null;
    }, []);

    void update() async {
      if (isWindows) {
        String resolvedExecutablePath = Platform.resolvedExecutable;
        String path = p.dirname(resolvedExecutablePath);
        String batFilePath = p.join(path, 'iris-updater.bat');
        // 执行 bat 文件
        await Process.start(
          'cmd.exe',
          ['/c', batFilePath],
          mode: ProcessStartMode.detached,
          runInShell: true,
        );
        // 退出应用：先走统一关停链解绑 mpv 回调（否则 isolate 关闭后 mpv
        // 线程的唤醒回调会触发 VM FATAL），再瞬时终止进程，让 updater 尽快
        // 拿到可写的 exe。bat 到真正覆盖文件前还要重新下载 + 解压 +
        // `timeout /t 2`，远长于关停链的 5s 硬上限。
        await AppShutdown.run();
        exit(0);
      }
    }

    Future<void> cancel() async {
      if (context.mounted) {
        Navigator.pop(context, 'Cancel');
      }
    }

    return AlertDialog(
      title: Text('${t.checked_new_version}: ${release.version}'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
        ),
        child: SingleChildScrollView(
          child: MarkdownBody(data: release.changeLog, shrinkWrap: true),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: cancel,
          child: Text(t.cancel),
        ),
        TextButton(
          onPressed: () => launchURL(release.url),
          child: Text(t.releasePage),
        ),
        // Visibility(
        //   visible: !isDesktop,
        //   child: TextButton(
        //     onPressed: () {
        //       launchURL(release.url);
        //       Navigator.pop(context, 'OK');
        //     },
        //     child: Text(t.download),
        //   ),
        // ),
        Visibility(
          visible: isDesktop && updateScriptIsExists.value,
          child: TextButton(
            onPressed: update,
            child: Text(
                '${t.download_and_update} (${fileSizeConvert(release.size)} MB)'),
          ),
        ),
      ],
    );
  }
}

/// 连接层集中调参入口（2026-11-20 新增，跨网络快速配对重构）。
///
/// 背景：这次重构要让「同一手机 + 同一 PC 在两个网络各扫码一次后，回到任一
/// 网络 1~2 秒内自动连上」。为此引入了 Happy Eyeballs 并行竞速、网络画像
/// 感知的候选排序和地址簿历史。竞速的 stagger/超时/预算、网络快照防抖、
/// 地址簿评分权重全部集中在本文件，避免魔法数字散落在 controller / race /
/// address book 三处；单元测试通过构造不同参数的 const 实例来压缩等待时间。
///
/// 注意：本文件只放「可调参数」与纯函数权重计算，不产生任何 IO。
library;

/// 连接层超时与竞速参数。
///
/// 预算推导（目标：回到已知网络 1~2 秒内完成配对）：
/// - 单候选握手探测 1200ms（已知网络）/ 2000ms（未知网络）；
/// - 第 i 个候选延迟 120ms * i 启动，最多 3 路并行；
/// - 整体竞速预算 2800ms，到点即放弃并交给原有 backoff 轮询。
class ConnectionTuning {
  const ConnectionTuning({
    this.raceStagger = const Duration(milliseconds: 120),
    this.raceWidth = 3,
    this.savedRaceCandidateCount = 3,
    this.knownNetworkAttemptTimeout = const Duration(milliseconds: 1200),
    this.unknownNetworkAttemptTimeout = const Duration(milliseconds: 2000),
    this.raceBudget = const Duration(milliseconds: 2800),
    this.networkChangeDebounce = const Duration(milliseconds: 400),
    this.nativeSnapshotTimeout = const Duration(milliseconds: 800),
    this.qrResultRevealDelay = const Duration(milliseconds: 760),
    this.qrSuccessHoldDelay = const Duration(milliseconds: 1100),
    this.qrFailureHoldDelay = const Duration(milliseconds: 1700),
    this.addressBookMaxAddresses = 12,
    this.addressWeights = const AddressBookWeights(),
  });

  /// 第 i 个候选的启动延迟 = [raceStagger] * i（Happy Eyeballs 的 stagger）。
  final Duration raceStagger;

  /// 同时进行的最大探测数；超出的候选等空位后按 stagger 顺延。
  final int raceWidth;

  /// 已保存设备重连时，只把评分最高的前 N 个候选投入竞速。
  final int savedRaceCandidateCount;

  /// 当前网络画像已知时，单个候选的建链+握手探测超时。
  final Duration knownNetworkAttemptTimeout;

  /// 网络画像未知（退化为 Dart 近似或拿不到接口）时放宽单候选超时。
  final Duration unknownNetworkAttemptTimeout;

  /// 一次并行竞速的整体预算；到点返回 null，进入原有 backoff。
  final Duration raceBudget;

  /// 原生网络状态事件到 Dart 快照的防抖窗口，避免网络抖动时反复重启竞速。
  final Duration networkChangeDebounce;

  /// 原生 getNetworkSnapshot 的等待上限；超时则本次退化为 Dart 回退实现。
  final Duration nativeSnapshotTimeout;

  /// QR 扫码配对的结果展示时间，保持原 UI 语义（760ms reveal + hold）。
  final Duration qrResultRevealDelay;
  final Duration qrSuccessHoldDelay;
  final Duration qrFailureHoldDelay;

  /// 地址簿裁剪上限（软上限：不同 networkKey 的最近成功地址永不裁剪）。
  final int addressBookMaxAddresses;

  /// 地址簿候选评分权重。
  final AddressBookWeights addressWeights;

  /// 按当前网络画像是否已知选择单候选超时。
  Duration attemptTimeoutFor({required bool networkKnown}) {
    return networkKnown
        ? knownNetworkAttemptTimeout
        : unknownNetworkAttemptTimeout;
  }
}

/// 地址簿候选评分权重（2026-11-20 新增）。
///
/// 分层规则（数值差距保证「同 networkKey > 同子网 > Tailscale」的严格优先）：
/// 1. 候选 networkKey == 当前 networkKey：+1000（这个地址在本网络成功过）；
/// 2. 候选 IP 落在当前本地子网：+800（同网段通常可达）；
/// 3. 双端 Tailscale（100.64.0.0/10）：+700（VPN 隧道内稳定可达）；
/// 4. 本地有 Tailscale 而候选是私有 LAN 地址：-100（可能被 VPN lockdown 挡）；
/// 5. 本地网络已知、候选是「别的网络的私有 LAN 地址」：-300，
///    典型是 PC 的 docker 网段（如 172.17.0.0/16）或旧 WiFi 网段，
///    当前手机上不可路由，必须被压到同网段候选之后；
/// 6. 再叠加最近成功时间（0~200）与成功/失败计数（±几十）做次级排序。
///
/// 失败计数在 recordSuccess 时递减，因此一次网络抖动造成的降权会被后续
/// 成功逐步抵消；未知网络时 1~5 全为 0，只靠 6 与 IP 字典序得到稳定顺序。
class AddressBookWeights {
  const AddressBookWeights({
    this.networkKeyMatchBonus = 1000,
    this.sameSubnetBonus = 800,
    this.dualTailscaleBonus = 700,
    this.localTailscaleLanPenalty = -100,
    this.foreignPrivateLanPenalty = -300,
    this.recentSuccessMaxBonus = 200,
    this.recentSuccessDayBonus = 120,
    this.recentSuccessWeekBonus = 50,
    this.recentSuccessStaleBonus = 20,
    this.successStepBonus = 12,
    this.successCap = 8,
    this.failureStepPenalty = -18,
    this.failureCap = 6,
  });

  final int networkKeyMatchBonus;
  final int sameSubnetBonus;
  final int dualTailscaleBonus;
  final int localTailscaleLanPenalty;
  final int foreignPrivateLanPenalty;

  /// 最近成功时间加分：1 小时内满分，1 天内/1 周内/更久逐级衰减。
  final int recentSuccessMaxBonus;
  final int recentSuccessDayBonus;
  final int recentSuccessWeekBonus;
  final int recentSuccessStaleBonus;

  /// 成功计数每个 +12（封顶 8 个）；失败计数每个 -18（封顶 6 个）。
  final int successStepBonus;
  final int successCap;
  final int failureStepPenalty;
  final int failureCap;

  /// 最近成功时间加分；从未成功返回 0。
  int recencyBonus({required int lastSuccessTs, required int nowMs}) {
    if (lastSuccessTs <= 0) {
      return 0;
    }
    final ageMs = nowMs - lastSuccessTs;
    if (ageMs <= const Duration(hours: 1).inMilliseconds) {
      return recentSuccessMaxBonus;
    }
    if (ageMs <= const Duration(days: 1).inMilliseconds) {
      return recentSuccessDayBonus;
    }
    if (ageMs <= const Duration(days: 7).inMilliseconds) {
      return recentSuccessWeekBonus;
    }
    return recentSuccessStaleBonus;
  }

  /// 成功/失败计数加分（失败为负），两者都封顶，避免历史无限放大。
  int countsBonus({
    required int successCount,
    required int failureCount,
  }) {
    final successes =
        successCount < 0 ? 0 : (successCount > successCap ? successCap : successCount);
    final failures =
        failureCount < 0 ? 0 : (failureCount > failureCap ? failureCap : failureCount);
    return successes * successStepBonus + failures * failureStepPenalty;
  }
}

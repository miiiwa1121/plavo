import PlavoCore
import SwiftUI

/// 観察中の株を選ぶ弧（D39 / D41）。
///
/// iPhone のカメラでズームを長押ししたときの円弧に倣う。
/// 画面の左端に半円が付き、押さえたまま待つと**その半円が広がって**
/// 株の名前が弧に沿って並ぶ。
///
/// **画像による個体同定はやめた。**同じ品種を画像で区別するのは精度が出にくく、
/// 間違えると記録が別の株に混ざる。人が選ぶほうが確実で、実装も軽い。
///
/// **選び方はダイヤル（D41）。**指定の場所（弧の頂点）は動かず、名前のほうが
/// 回ってくる。指を離した時点で頂点にあるものが決まる。
///
/// ## 部品の呼び方
///
/// 話すときと書くときで名前が違うと、どこを直しているのか通じない。
/// **タブバーを手本にしているので、対応する部品には対応する名前を付ける。**
///
/// | 呼び方 | タブバー（手本） | サイドバー（この弧） | コード |
/// |---|---|---|---|
/// | 全体枠 | バーそのもの | 通常円 / 拡大円 | `ArcSegment` |
/// | 囲い枠 | 選択中を囲う塊 | 名前を囲う塊 | `nameFrame*` |
/// | 文字 | 項目名＋アイコン | 名前 | `names` / `nameLabel` |
///
/// - **通常円** … 触っていないときの小さな半円（`restingRadius`）
/// - **拡大円** … 触っているときの大きな弧（`expandedRadius`）
///
/// **見た目の材料も手本に合わせる。**全体枠（通常円・拡大円）はタブバー本体と
/// 同じ Liquid Glass、囲い枠はタブバーの選択中と同じ**べた塗りの塊**。
/// 以前は逆で、囲い枠のほうがガラスだった。
struct PlantSelectorArc: View {
    @Bindable var model: AppModel
    /// ガジェットが株を決めたときに変わる。合図として受け取る
    let autoSelectedAt: Date?
    /// 周囲の明るさ 0〜1。地を白にするか黒にするかをこれで決める
    var ambientBrightness: Double = 0.3
    /// 弧を退かせるか。
    ///
    /// **「迎える」に切り替えているあいだ、弧は退く。**これから新しい株を
    /// 迎えようとしているのに、いま選ばれている株の名前が出ていると
    /// 相手を取り違える。小さくして、何も指さない形にする。
    ///
    /// 選択肢の「未設定」（`Choice.unassigned`）とは別物。あちらは選べる先で、
    /// こちらは弧そのものが下がっている状態。
    var receding: Bool = false

    @State private var expanded = false
    @State private var collapseTask: Task<Void, Never>?

    /// 押し始めてから開くまでの間。
    /// 触れた瞬間に開くと長押しの感じがなく、意図せず開いてしまう
    private let pressBeforeOpen: Duration = .milliseconds(175)
    /// 開いたあと、触られなければ自動で閉じるまでの時間。
    ///
    /// **離してから決まる方式にしたので、少し長く残す。**
    /// 即座に畳むと、何が選ばれたのかを見る間がない。
    private let idleBeforeCollapse: Duration = .seconds(0.4)

    /// 縦の置き場所。画面中央からのずれ。持ち方に合わせて動かせる
    /// 未設定なら 0。`object(forKey:) as? Double` は型が合わず取りこぼす
    @State private var barOffset: CGFloat = UserDefaults.standard.double(forKey: "arcOffset")
    @State private var dragBaseOffset: CGFloat = 0
    @State private var pressTask: Task<Void, Never>?
    @State private var mode: Mode = .idle

    /// 名前の列の回転量（度）。0 のとき先頭が指定の場所に来る。
    /// 下へ回すほど増え、前の名前が降りてくる
    @State private var wheelAngle: Double = 0
    /// 回し始めたときの回転量。指の移動量をここに足す
    @State private var wheelAngleAtDragStart: Double = 0
    /// 直前に触覚を鳴らした位置。同じところで鳴り続けないように持つ
    @State private var lastFeedbackIndex: Int = -1
    /// 名前の実寸。塊の大きさをこれに合わせる
    @State private var itemSizes: [String: CGSize] = [:]
    /// 切っていないときの名前の幅。**見えているほうを測ってはいけない。**
    /// 切る→縮む→収まる→戻す、を毎フレーム繰り返す
    @State private var naturalWidths: [String: CGFloat] = [:]

    /// 触れたあと、指の動きで何をするかが決まる
    private enum Mode {
        case idle
        /// すぐ上下に動かした → バーの置き場所を変える
        case moving
        /// 押さえたまま → 名前を回して選ぶ
        case selecting
    }

    /// これ以上動いたら「移動」とみなす
    private let moveThreshold: CGFloat = 10

    // 閉じているとき。中心が画面の端にあるので、半円がそのまま見える。
    // 退いているときは、さらに小さくする
    private var restingRadius: CGFloat { receding ? 22 : 40 }
    private let restingCenterX: CGFloat = 0

    // 開いたとき。
    // **中心を画面の外へ出し、大きな円の浅い一部だけを見せる。**
    // iPhone のカメラのズームと同じ作り。円を丸ごと描き、
    // 画面の縁が切り取ることで、縁から生えた弧になる。
    /// 半径と中心の差が、画面に出っ張る量になる。
    ///
    /// 形は「出っ張り ÷ 縦半分」の比で決まる。参考にした iPhone のズームは
    /// この比が約 0.63。中心を縁に寄せるほど深い弧に、遠ざけるほど浅くなる。
    /// 半径は弧全体の大きさを、中心の位置は深さを決める。
    private let expandedRadius: CGFloat = 169
    /// 中心の横位置。負の値だけ画面の外に出る
    private let expandedCenterX: CGFloat = -73

    /// 名前1つあたりの角度。
    ///
    /// **全体の広がりではなく、間隔。**名前は回るので、数が増えても
    /// 弧が詰まることはない。入りきらないぶんは端で消える。
    ///
    /// **同時に5つ見えるように決めた。**弧の中心は画面の外（x = -73）にあり、
    /// 名前は半径 147 の上に乗るので、角度が開くほど左へ寄る。
    /// 2つ外側（32°）でも x = 52 に残る間隔がこれ。
    private let step: Double = 16
    /// このぶん指を動かすと、名前が1つ進む
    private let pointsPerStep: CGFloat = 44
    /// ここまでは、はっきり見せる角度
    private let clearAngle: Double = 24
    /// ここを越えたら消す角度。名前が画面の左に流れ出る前に消す。
    ///
    /// **止まっているとき、6つ目がちょうど消えるところに置く**（16° × 3）。
    /// 中途半端に残ると、画面の縁で切れた文字が見える
    private let fadeAngle: Double = 48

    /// 弧に並ぶ選択肢。株に加えて「未設定」を持つ。
    ///
    /// **未設定を選べることに意味がある。**選ぶと誰も見ていない状態に戻り、
    /// カメラは見当たらない扱いになる（D40-a）。観察をやめる操作。
    private enum Choice: Identifiable {
        case unassigned
        case plant(Plant)

        var id: String {
            switch self {
            case .unassigned: "unassigned"
            case .plant(let plant): plant.id.uuidString
            }
        }

        var label: String {
            switch self {
            case .unassigned: "未設定"
            case .plant(let plant): plant.name
            }
        }

        var plantId: UUID? {
            switch self {
            case .unassigned: nil
            case .plant(let plant): plant.id
            }
        }

        var plant: Plant? {
            switch self {
            case .unassigned: nil
            case .plant(let plant): plant
            }
        }
    }

    /// 先頭が「未設定」。以降が株の並び
    private var choices: [Choice] {
        [.unassigned] + model.store.plants.map { Choice.plant($0) }
    }

    /// いま選ばれているものの位置。株が見つからなければ「未設定」
    private var selectedIndex: Int {
        guard let id = model.store.selectedPlantId,
            let i = model.store.plants.firstIndex(where: { $0.id == id })
        else { return 0 }
        return i + 1
    }

    /// いま指定の場所にあるもの。離せばこれに決まる
    private var highlightIndex: Int {
        let raw = (-wheelAngle / step).rounded()
        return min(max(Int(raw), 0), max(0, choices.count - 1))
    }

    // MARK: - 地の明暗（タブバーに合わせる）

    /// 地を明るいほうにするか。
    ///
    /// **タブバーと同じで、白か黒のどちらか。**タブバーは周りの明るさで
    /// 白い地と黒い地を切り替えるが、途中の灰色は作らない。
    /// 弧だけが連続で変わると、同じ画面に並んだときに別の作りに見える。
    @State private var lightChrome = false

    /// 切り替わる明るさ。**入る値と出る値をずらしてある。**
    /// 1つの境目だと、境目付近で明るさが揺れるたびに白黒が往復する
    private let toLightAt: Double = 0.58
    private let toDarkAt: Double = 0.42

    /// 全体枠（通常円・拡大円）の色。
    ///
    /// **ガラスに掛ける色として使う。**タブバーの地と同じ明暗を、
    /// 実測した明るさから決める。濃さは 0.82 で固定
    private var chromeTint: Color {
        Color(white: lightChrome ? 0.92 : 0.06).opacity(0.82)
    }

    /// 選ばれていない名前の色。地が白へ回れば、文字は黒へ回る
    private var nameColor: Color {
        lightChrome ? .black.opacity(0.66) : .white.opacity(0.72)
    }

    /// 囲い枠の塗り。**塊はいつも地より明るい**（タブバーの選択中と同じ）。
    /// 暗い地には薄く白を重ね、明るい地では白で塗り切って持ち上げる
    private var nameFrameFill: Color {
        .white.opacity(lightChrome ? 0.92 : 0.20)
    }

    /// ガラスの縁の光沢を、どれだけ削るか。
    ///
    /// **縁そのものは残す。**タブバーの全体枠にも縁の光沢はあり、
    /// 消してしまうと材料が違って見える。ただし**弧は輪郭の片側しか
    /// 見えないぶん、同じ光沢でも一本の線として強く出る。**
    ///
    /// 削り方は「この幅だけ大きく描いて、元の大きさで切る」（`arcVisual`）。
    /// 0 なら手を加えない。増やすほど、いちばん明るいところから順に落ちる。
    ///
    /// **暗い地のほうを多く削る。**白い光沢は黒地でいちばん際立つ。
    /// 明るい地では地に紛れるので、ほとんど削らなくていい。
    private var glassRimTrim: CGFloat { lightChrome ? 0.5 : 1.5 }

    /// 弧のいちばん出っ張るところの横位置
    private var apexX: CGFloat { expandedRadius + expandedCenterX }
    /// 弧の縁から、頂点の印までの間。
    /// 名前がここまで届くことは無い（6文字でも縁の手前で終わる）
    private let iconGap: CGFloat = 32

    private var radius: CGFloat { expanded ? expandedRadius : restingRadius }
    private var centerX: CGFloat { expanded ? expandedCenterX : restingCenterX }
    /// 名前を並べる弧の半径。塗りの縁より少し内側に置く
    /// 弧の縁から内側に取る余白
    private let edgeInset: CGFloat = 6
    private let namePadding: CGFloat = 10
    private let nameFont: Font = .caption.weight(.medium)

    /// その角度で名前に使える範囲。半径で表す。
    ///
    /// **名前は半径に沿って寝ているので、外へはみ出すかは半径で決まる。**
    ///   外側 … 弧の縁（`expandedRadius`）
    ///   内側 … 画面の左端。円の中心が画面の外にあるぶん、角度が開くほど遠のく
    ///
    /// 角度が開くほど狭くなるので、端の名前は短く切られる。
    private func nameSpan(at angle: Double) -> (center: CGFloat, width: CGFloat) {
        let outer = expandedRadius - edgeInset
        let inner = -expandedCenterX / max(0.2, CGFloat(cos(angle * .pi / 180))) + edgeInset
        return ((inner + outer) / 2, max(30, outer - inner))
    }

    /// 閉じているときに名前を畳んでおく位置
    private var restingNameRadius: CGFloat { restingRadius * 0.5 }
    /// 頂点で名前が置かれる半径。印もここに合わせる
    private var apexNameRadius: CGFloat { nameSpan(at: 0).center }

    var body: some View {
        GeometryReader { geo in
            let centerY = geo.size.height / 2 + barOffset

            ZStack(alignment: .topLeading) {
                // **閉じた半円と開いた弧を、同じ図形の変形として扱う。**
                // 別のビューに差し替えると、消えて出てくる動きになり、
                // 「広がった」ように見えない。
                // 帯は自分の枠の中央を弧の中心にする。
                // 名前は centerY（＝画面中央＋ずらし）を基準に置くので、
                // **帯にも同じずらしを掛けないと、動かしたときに離れる。**
                // **円を丸ごと描き、画面の縁で切る。**
                // 帯にすると縁から浮いてしまい、貼り付いて見えない。
                arcVisual(height: geo.size.height)

                // 囲い枠。回している間だけ伸びて、出入りする名前をまたぐ
                nameFrameVisual(centerY: centerY)

                // **名前は2枚重ねる。**下地は塊の形で抜き、
                // アクセント色は塊の形だけ出す。
                // こうすると**塊が半分かかった名前は、半分だけ色が変わる。**
                // フェードではなく、膜が通り過ぎた側から変わる（タブバーと同じ）
                names(centerY: centerY, style: AnyShapeStyle(nameColor))
                    .mask { punchedOut(centerY: centerY) }

                names(centerY: centerY, style: AnyShapeStyle(Color.accentColor))
                    .mask { nameFrameShape(centerY: centerY, fill: .white) }

                apexIcon(centerY: centerY)

                // 触る場所は状態をまたいで1つに保つ。
                // 開いた瞬間にビューが入れ替わると、その上のジェスチャが切れる
                let hit = hitSize
                Color.clear
                    .frame(width: hit.width, height: hit.height)
                    .contentShape(Rectangle())
                    .offset(y: centerY - hit.height / 2)
                    .gesture(arcGesture(height: geo.size.height))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .animation(.spring(duration: 0.34, bounce: 0.18), value: expanded)
        // 回転そのものは指に付けるため動かさない。
        // 頂点の印だけは、そのままだと点滅して見えるので馴染ませる
        .animation(.easeOut(duration: 0.16), value: highlightIndex)
        .animation(.spring(duration: 0.3), value: receding)
        // 指す先が無いあいだは触れない。
        // 開いて選べてしまうと、選んだのに名前が出ない状態になる
        .allowsHitTesting(!receding)
        // 地の明暗はここで決める。**弧の中で連続値を色に変えない。**
        // 変えると白黒のあいだの灰色ができ、タブバーと作りが違ってしまう
        .onAppear { lightChrome = ambientBrightness >= toLightAt }
        .onChange(of: ambientBrightness) { _, value in
            let next = value >= (lightChrome ? toDarkAt : toLightAt)
            guard next != lightChrome else { return }
            // 切り替わりは目に付くので、色だけをゆっくり移す
            withAnimation(.easeInOut(duration: 0.28)) { lightChrome = next }
        }
        .onChange(of: receding) { _, value in
            guard value else { return }
            collapseTask?.cancel()
            expanded = false
        }
        .onChange(of: autoSelectedAt) { _, value in
            // 黙って切り替わると気づけない。一度開いて見せる（D39）
            guard value != nil else { return }
            alignToSelection()
            expanded = true
            scheduleCollapse()
        }
    }

    // MARK: - 名前

    /// 名前をひと並び分。**同じ配置で2回描く**ので、層として切り出してある。
    ///
    /// 色だけを差し替えて重ね、塊の形で出し分ける。
    /// 配置が1文字でもずれると、色の境目が名前とずれて見える。
    private func names(centerY: CGFloat, style: AnyShapeStyle) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                let a = angle(index)
                nameLabel(choice, maxWidth: nameSpan(at: a).width)
                    .foregroundStyle(style)
                    .rotationEffect(.degrees(expanded ? a : 0))
                    .position(position(angle: a, centerY: centerY))
                    .opacity(opacity(index: index, angle: a))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 弧に並ぶ1項目。**文字の大きさは選択で変えない。**
    /// タブバーは選択中の文字を大きくせず、色と塊だけで示す。
    ///
    /// **アイコンは項目ごとには付けない。**写真を入れるまで株のアイコンは
    /// どれも同じ記号なので、並べても見分けがつかず、
    /// 名前の幅が増えて弧からはみ出すだけだった。
    /// 頂点のものだけ、円の外側に固定した印として出す（`apexIcon`）。
    /// 与えられた範囲に収める。**収まらなければ「…」で切る。**
    ///
    /// 自然な幅は、切っていない控えを隠して置いて測る。見えているほうを
    /// 測ると「切る→縮む→収まる→戻す」を繰り返して落ち着かない。
    private func nameLabel(_ choice: Choice, maxWidth: CGFloat) -> some View {
        let room = max(24, maxWidth - namePadding * 2)
        let width = min(naturalWidths[choice.id] ?? room, room)
        return Text(choice.label)
            .font(nameFont)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width)
            .padding(.horizontal, namePadding)
            .padding(.vertical, 5)
            .background {
                Text(choice.label)
                    .font(nameFont)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                        naturalWidths[choice.id] = $0
                    }
            }
            // 塊の大きさを名前に合わせるため、実寸を測って覚えておく
            .onGeometryChange(for: CGSize.self) { $0.size } action: { itemSizes[choice.id] = $0 }
    }

    // MARK: - 全体枠（通常円・拡大円）

    /// 通常円と拡大円の見た目。**タブバー本体と同じ Liquid Glass を使う。**
    ///
    /// 以前はここが実測した明るさのべた塗りで、ガラスは囲い枠のほうに
    /// 付いていた。**手本と逆だった。**タブバーでガラスなのはバー本体で、
    /// 選択中の塊はべた塗りの塩梅。付け替えた。
    ///
    /// **色（`chromeTint`）を掛けて使う。**ぼかし（Material /
    /// `UIVisualEffectView`）は ARKit が Metal で描くカメラ映像を取り込めず、
    /// 素材を置いても地の色が出るだけだった。ガラスが同じなら、無着色では
    /// 周りが明るくても暗くても同じ見え方になる。実測した明るさから作った色を
    /// 掛けておけば、取り込めていなくても**タブバーと同じ明暗に付いてくる。**
    ///
    /// 通常円と拡大円は**同じ図形の変形**として扱う。別のビューに差し替えると、
    /// 消えて出てくる動きになり「広がった」ように見えない。
    ///
    /// **縁の光沢は弱める。消しはしない。**タブバーの全体枠にも同じ光沢があり、
    /// 無くすと材料が違って見える。ただし**弧は輪郭の片側しか見えないぶん、
    /// 同じ光沢でも一本の白線として強く出る**——タブバーでは枠を一周するので
    /// 線ではなく丸みとして馴染む。
    ///
    /// 強さを直す設定は材料側に無いので、**削る幅だけ大きく描いて、
    /// 元の大きさで切る**（`glassRimTrim`）。いちばん明るいところが
    /// 切り取られた外側に落ち、内側の淡いところだけが残る。
    /// 縁取りを重ねて隠す手もあるが、地が半透明なのでそこだけ濃くなる。
    ///
    /// iOS 26 より前ではガラスが無いので、色だけのべた塗りに落ちる。
    @ViewBuilder
    private func arcVisual(height: CGFloat) -> some View {
        let shape = ArcSegment(radius: radius, centerX: centerX)
        // 名前は centerY（＝画面中央＋ずらし）を基準に置くので、
        // **弧にも同じずらしを掛けないと、動かしたときに離れる。**
        let width = expandedRadius + expandedCenterX + 12
        if #available(iOS 26.0, *) {
            Color.clear
                .frame(width: width, height: height)
                // 大きくするのはガラスのほうだけ。切る形は元のまま。
                // **弧の大きさは変えない**——頂点の位置（`apexX`）は
                // アイコンの置き場所と触れる範囲の基準になっている
                .glassEffect(
                    .regular.tint(chromeTint),
                    in: ArcSegment(radius: radius + glassRimTrim, centerX: centerX))
                .clipShape(shape)
                .offset(y: barOffset)
        } else {
            shape
                .fill(chromeTint)
                .frame(width: width, height: height)
                .offset(y: barOffset)
        }
    }

    // MARK: - 囲い枠

    /// 囲い枠の大きさ。**回している間だけ縦に伸びる。**
    ///
    /// タブバーは印のほうが項目から項目へ伸びて移るが、弧では逆に
    /// **印が止まっていて名前が動く。**そこで、頂点にある名前が頂点から
    /// 離れているぶんだけ塊を伸ばす。半分まで来たところで最も長くなり、
    /// **出ていく名前と入ってくる名前の両方をまたぐ。**止まると元に戻る。
    ///
    /// 幅は包んでいる名前の実寸から決める。短い名前に長い塊が付くと、
    /// 何を指しているのか分からなくなる。
    private var nameFrameSize: CGSize {
        guard expanded, !receding, highlightIndex < choices.count else { return .zero }
        let base = itemSizes[choices[highlightIndex].id] ?? CGSize(width: 56, height: 24)

        // 頂点にある名前が、頂点からどれだけ離れているか
        let a = angle(highlightIndex)
        let reach = abs(nameSpan(at: a).center * CGFloat(sin(a * .pi / 180)))

        // 近づいてくる隣。半分まで来たら、その幅まで包めるようにする
        let neighbor = a > 0 ? highlightIndex - 1 : highlightIndex + 1
        let neighborWidth: CGFloat =
            (0..<choices.count).contains(neighbor)
            ? (itemSizes[choices[neighbor].id]?.width ?? base.width) : base.width
        let t = min(1, abs(a) / (step / 2))
        let width = base.width + (max(base.width, neighborWidth) - base.width) * t

        return CGSize(width: width, height: base.height + reach * 2)
    }

    /// 目に見える囲い枠。**タブバーの選択中と同じ、べた塗りの塊。**
    ///
    /// ガラスはここではなく全体枠（`arcVisual`）が持つ。**囲い枠は
    /// すでにガラスの上に乗っているので、重ねてもぼかす先が無い。**
    /// 手本のタブバーでも、選択中を示しているのは無彩色の塗りひとつ。
    ///
    /// **着色しない。**色が付いているのは中身（名前）のほうだけ。
    /// 塊を青くすると、同じ色の名前が読めなくなる。
    private func nameFrameVisual(centerY: CGFloat) -> some View {
        nameFrameShape(centerY: centerY, fill: nameFrameFill)
    }

    /// 囲い枠の形。**見えるほうにも、名前を切り抜くマスクにも、これを使う。**
    /// 形が1か所から出ているので、色の境目が枠とずれることがない
    private func nameFrameShape(centerY: CGFloat, fill: Color) -> some View {
        Capsule()
            .fill(fill)
            .frame(width: nameFrameSize.width, height: nameFrameSize.height)
            .position(x: centerX + apexNameRadius, y: centerY)
    }

    /// 塊の形だけを抜いた面。下地の名前はこれで隠す。
    /// **抜かずに上へ色を重ねると、下の白が透けて色が濁る。**
    private func punchedOut(centerY: CGFloat) -> some View {
        Rectangle()
            .fill(.white)
            .overlay {
                nameFrameShape(centerY: centerY, fill: .white).blendMode(.destinationOut)
            }
            .compositingGroup()
    }

    /// 頂点に来ているものを、**円の外側の決まった場所**で示す印。
    ///
    /// 名前には付けない。名前に添えると**その長さで位置が動き**、
    /// 「ここが頂点だ」という印としての意味が薄れる。
    /// 場所を動かさないからこそ、名前のほうが回っていることが分かる。
    ///
    /// 弧の塗りの外に出るので、映像の上に独立して立つ。縁取りと影を付ける。
    /// 「未設定」にはアイコンが無いので、そのときは何も出ない。
    @ViewBuilder
    private func apexIcon(centerY: CGFloat) -> some View {
        if expanded, highlightIndex < choices.count,
            let plant = choices[highlightIndex].plant
        {
            PlantAvatar(plant: plant, model: model, size: 26)
                .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
                // **円の中心の側（左）から出て、そちらへ引っ込む。**
                //
                // `.transition` は `.position` より内側に置く。外側に置くと、
                // 変形するのは「画面いっぱいに広がった位置決めの器」のほうで、
                // その中心＝画面の中央を起点に出入りして見えていた。
                .transition(.offset(x: -46).combined(with: .opacity))
                .position(x: apexX + iconGap, y: centerY)
        }
    }

    /// 指定の場所（弧の頂点）から測った角度。下が正
    private func angle(_ index: Int) -> Double {
        Double(index) * step + wheelAngle
    }

    /// 閉じているときは半円の中に重ね、開くと弧に沿って散る。
    /// 位置が補間されるので、名前が扇のように開く
    private func position(angle a: Double, centerY: CGFloat) -> CGPoint {
        guard expanded else {
            return CGPoint(x: restingNameRadius, y: centerY)
        }
        let r = a * .pi / 180
        return CGPoint(
            x: centerX + nameSpan(at: a).center * cos(r),
            y: centerY + nameSpan(at: a).center * sin(r))
    }

    private func opacity(index: Int, angle a: Double) -> Double {
        // 退いているあいだは、名前をひとつも出さない
        if receding { return 0 }
        // **閉じているときは名前を出さない。**
        // 決まっている株の名前は画面の上（アイコンの下）に出るので、
        // ここに出すと二重になる。弧は触るまで無地の半円でいる
        guard expanded else { return 0 }
        let m = abs(a)
        if m <= clearAngle { return 1 }
        if m >= fadeAngle { return 0 }
        return (fadeAngle - m) / (fadeAngle - clearAngle)
    }

    // MARK: - 触れる範囲とジェスチャ

    private var hitSize: CGSize {
        guard expanded else {
            return CGSize(width: restingRadius + 12, height: restingRadius * 2)
        }
        // 名前が見えている縦幅に、掴みやすいだけの余裕を足す
        let vertical = 2 * nameSpan(at: fadeAngle).center * sin(fadeAngle * .pi / 180) + 120
        return CGSize(width: expandedRadius + expandedCenterX + 24, height: vertical)
    }

    /// 押す・回す・動かすを1つのジェスチャで扱う。
    ///
    /// | 指の動き | 何が起きるか |
    /// |---|---|
    /// | すぐ上下に動かす | バーの置き場所を変える |
    /// | 押さえたまま待つ | 弧が開き、そのまま上下に滑らせて名前を回す |
    private func arcGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                collapseTask?.cancel()

                switch mode {
                case .idle:
                    if expanded {
                        beginTurning(from: v.translation.height)
                        return
                    }
                    if abs(v.translation.height) > moveThreshold {
                        pressTask?.cancel()
                        pressTask = nil
                        mode = .moving
                        dragBaseOffset = barOffset
                    } else if pressTask == nil {
                        pressTask = Task {
                            try? await Task.sleep(for: pressBeforeOpen)
                            guard !Task.isCancelled else { return }
                            alignToSelection()
                            expanded = true
                            beginTurning(from: v.translation.height)
                        }
                    }

                case .moving:
                    barOffset = clamp(dragBaseOffset + v.translation.height, height: height)

                case .selecting:
                    turn(to: v.translation.height)
                }
            }
            .onEnded { _ in
                pressTask?.cancel()
                pressTask = nil
                if mode == .moving {
                    UserDefaults.standard.set(Double(barOffset), forKey: "arcOffset")
                } else if mode == .selecting {
                    commit()
                } else if expanded {
                    scheduleCollapse()
                }
                mode = .idle
            }
    }

    /// 画面からはみ出さない範囲に収める。
    ///
    /// 見える弧の縦の広がりは、円の半径と中心の位置から決まる。
    /// 半径そのものではない——大半が画面の外にあるため。
    private func clamp(_ value: CGFloat, height: CGFloat) -> CGFloat {
        let visibleHalfHeight = sqrt(
            max(0, expandedRadius * expandedRadius - expandedCenterX * expandedCenterX))
        let limit = max(0, height / 2 - visibleHalfHeight - 24)
        return min(limit, max(-limit, value))
    }

    // MARK: - 回して選ぶ

    /// 回し始める。**いまの回転量を基点にする。**
    /// 開いた時点ですでに指が動いているので、その移動量を差し引く
    private func beginTurning(from translation: CGFloat) {
        mode = .selecting
        wheelAngleAtDragStart = wheelAngle - Double(translation) / Double(pointsPerStep) * step
        lastFeedbackIndex = highlightIndex
        turn(to: translation)
    }

    /// 指の移動量を回転量に変える。
    ///
    /// 下へ引くと角度が増え、名前は下へ動く。前の名前が降りてくる——
    /// ピッカーと同じ向き。端では止める。ぐるりとは回らない
    private func turn(to translation: CGFloat) {
        let raw = wheelAngleAtDragStart + Double(translation) / Double(pointsPerStep) * step
        let last = Double(max(0, choices.count - 1)) * step
        wheelAngle = min(0, max(-last, raw))

        // 名前が指定の場所を通るたびに知らせる。
        // ダイヤルを回したときの、あの手触り
        let index = highlightIndex
        if index != lastFeedbackIndex {
            lastFeedbackIndex = index
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    /// 離した時点で指定の場所にあるものに決める。
    /// **通過しただけでは決まらない。**回している間はまだ見比べている段階
    private func commit() {
        let index = highlightIndex
        guard index < choices.count else { return }
        model.store.selectedPlantId = choices[index].plantId
        // 中途半端な角度で止めない。決まった位置へ寄せる
        withAnimation(.spring(duration: 0.24)) {
            wheelAngle = -Double(index) * step
        }
        scheduleCollapse()
    }

    /// いま決まっているものを、指定の場所に合わせる。
    /// 開いた瞬間に別のものが頂点にあると、回す前から選び直したように見える
    private func alignToSelection() {
        wheelAngle = -Double(selectedIndex) * step
        lastFeedbackIndex = selectedIndex
    }

    // MARK: - 開閉

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task {
            try? await Task.sleep(for: idleBeforeCollapse)
            guard !Task.isCancelled else { return }
            expanded = false
        }
    }
}

/// 画面の縁で切り取られる円。
///
/// 中心の横位置を負にすると、円の大半が画面の外へ出て、
/// 縁から生えた浅い弧になる。閉じているときは中心が縁の上にあるので、
/// そのまま半円として見える。
///
/// **帯（ドーナツ）にはしない。**縁から浮いてしまい、貼り付いて見えない。
private struct ArcSegment: Shape {
    var radius: CGFloat
    /// 円の中心の横位置。負の値だけ画面の外に出る
    var centerX: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(radius, centerX) }
        set {
            radius = newValue.first
            centerX = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        Path(
            ellipseIn: CGRect(
                x: centerX - radius, y: rect.midY - radius,
                width: radius * 2, height: radius * 2))
    }
}

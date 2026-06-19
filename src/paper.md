---
figureTitle: "Fig"
tableTitle: "Table"
figPrefix: "Fig"
tblPrefix: "Table"
secPrefix: "Section"
titleDelim: "."
---

<!--
  これは公開リポジトリ用の「サンプル原稿」です。
  内容はすべて明確なフィクション（パロディ）であり、実在の研究・人物・
  機関・データとは一切関係ありません。本ツール（Pandoc + Docker 抄録
  生成環境）の全機能を最小例で示すためのダミーです。
  This is a clearly fictional SAMPLE manuscript for the public repository.
  All names, data, and findings are parody and do not refer to any real
  research, person, institution, or dataset.
-->

::: {custom-style="標題（日本語）"}
とてつもない予感の定量化に向けたデバイス TJD と評価スケール THS の予備的検討
:::

::: {custom-style="著者（日本語）"}
予感 太郎^1^・直感 花子^2^・段 凡太^1^
:::

::: {custom-style="所属機関（日本語）"}
^1^とてつもない大学大学院 予感工学研究科，^2^バイブス総合研究所 直感情報部門
:::

::: {custom-style="標題（英語）"}
Toward Quantifying the Tremendous Hunch: A Preliminary Study of the TJD Device and the THS Scale
:::

::: {custom-style="著者（英語）"}
Taro Yokan^1^, Hanako Chokkan^2^, Bonta Dan^1^
:::

::: {custom-style="所属機関（英語）"}
^1^Graduate School of Hunch Engineering, University of the Tremendous, ^2^Department of Intuition Informatics, Vibes Research Institute
:::

Abstract: This sample manuscript is a deliberate parody used to demonstrate a reproducible authoring pipeline. We report a preliminary attempt to quantify the "tremendous hunch" felt by the first author upon waking. We built the Totetsumonai Jikken Device (TJD), a heavy and pointy apparatus that emits a low hum, and we defined the Totetsumonai Hyouka Scale (THS), a dimensional analysis that the SI system cannot express. In a pilot experiment in which the author stared intently at the TJD, we observed an effect of 2.6 tsu on the THS, with an error margin of about ±500%. The findings are gloriously inconclusive, which is precisely the point: the document itself was generated reproducibly by the toolchain described here.

Keywords: tremendous hunch, parody, reproducible documents, Pandoc, Docker, sample

抄録：本サンプル原稿は、再現可能な執筆パイプラインを実演するための明確なパロディである。筆者が起床直後に感じた「とてつもない予感」を定量化する予備的試みを報告する。予感を物理量へ変換するため、低い唸り声を上げる重く鋭利なデバイス「とてつもない実験デバイス（TJD）」を構築し、従来の SI 単位系では記述できない「とてつもない評価スケール（THS）」を定義した。筆者が TJD を凝視する予備実験において、THS で 2.6 tsu の効果を観測したが、誤差は概ね ±500% に及んだ。結論は壮大に不明瞭であるが、それこそが本質である。本文書自体が、ここで述べるツールチェーンによって再現可能に生成された。

キーワード：とてつもない予感，パロディ，再現可能文書，Pandoc，Docker，サンプル

<!-- セクション区切り: ここから2段組（汎用 A4 ジオメトリ。実テンプレ数値は転記しない） -->
```{=openxml}
<w:p>
  <w:pPr>
    <w:sectPr>
      <w:pgSz w:w="11906" w:h="16838" w:code="9"/>
      <w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417"
               w:header="720" w:footer="720" w:gutter="0"/>
      <w:cols w:space="425"/>
      <w:docGrid w:type="lines" w:linePitch="360"/>
    </w:sectPr>
  </w:pPr>
</w:p>
```

## 1. はじめに

近年、我が国における「予感」の重要性は高まっているかもしれないし、そうでもないかもしれない。しかし筆者が起床直後に抱いた「これはとてつもない予感のする研究である」という直感は、二度寝を妨げるほどの重力を持っていた[@yokan2099]。

従来の研究は「仮説」に基づいて行われるが、本研究は「予感」のみに基づいて遂行される点において画期的である。論理よりもパッションを、エビデンスよりもバイブスを重視する姿勢こそが、停滞する現代科学に物理的な風穴を開けうると考えた[@vibes2099]。本研究の目的は、筆者の抱くとてつもない予感を、客観的かつ「とてつもない」指標で可視化することである。

## 2. 方法

### 2.1 とてつもない実験デバイス（TJD）

予感を物理量へ変換するため **TJD（Totetsumonai Jikken Device）** を構築した。TJD は非常に重く、かつ鋭利な角を多数持つため、持ち運びやすさや安全性といった通常の指標でその良さを論じることは難しい。TJD は起動すると低い唸り声を上げ、周囲の空気をなんとなく重苦しくする機能を有する。実験条件の内訳を[@tbl:conditions]に示す。

::: {.textbox width="71mm" height="60mm" pos-x="109mm" pos-y="168mm" page="1"}
| 実験条件         | 試行数 | 割合   |
|:-----------------|-------:|-------:|
| 凝視             |     12 | 60.0%  |
| そっと触れる     |      5 | 25.0%  |
| 見て見ぬふり     |      3 | 15.0%  |
| **合計**         |     20 | 100.0% |

: 実験条件の内訳 {#tbl:conditions}
:::

### 2.2 とてつもない評価スケール（THS）

従来の SI 単位系では本研究の「とてつもなさ」を記述できない。そこで新たな次元解析として **THS（Totetsumonai Hyouka Scale）** を定義する。THS は予感の強さ $P$、冷や汗の量 $S$、教授の呆れ具合 $A$ を用いて次式で与えられる。

$$THS = \frac{P \times S}{A^2}$$

計測系の全体構成を[@fig:tjd-arch]に示す。

::: {.textbox width="71mm" height="75mm" pos-x="20mm" pos-y="20mm" valign="bottom" page="2"}
![TJD 計測系の全体構成（ダミー図）](src/figs/sample-architecture.svg){#fig:tjd-arch}
:::

## 3. 結果

予備実験（筆者が TJD を凝視する試行）により、THS で **2.6 tsu** の効果を観測した。これは実験開始時の「なんとなくすごい」という予感と概ね対応した数値であり、誤差は ±500% 程度に収まった。条件別の THS を[@fig:ths-trend]に示す。

::: {.textbox width="71mm" height="75mm" pos-x="109mm" pos-y="20mm" valign="bottom" page="2"}
![条件別の THS（ダミー図）](src/figs/sample-results.svg){#fig:ths-trend}
:::

## 4. 考察

結果より、TJD を凝視する条件において最も高い THS が得られることが示唆された。これは予感を高めるには対象を直視すべきという直感[@vibes2099]と整合する。一方で誤差 ±500% は無視できず、教授の呆れ具合 $A$ の測定法に課題が残る。

本サンプルの真の目的は、こうした図表・数式・引用・相互参照を含む文書が、Pandoc と Docker による決定的ビルドで再現可能に生成できることを示す点にある。

## 5. 結論

本研究では、とてつもない予感を定量化するための TJD と THS を提案し、予備的に 2.6 tsu の効果を観測した。結論は壮大に不明瞭だが、本文書自体が本ツールチェーンの出力であり、再現可能文書生成の最小実演となっている。

## 参考文献 {-}

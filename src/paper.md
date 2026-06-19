---
figureTitle: "Figure"
tableTitle: "Table"
figPrefix: "Figure"
tblPrefix: "Table"
secPrefix: "Section"
titleDelim: "."
---

<!--
  公開リポジトリ用の「サンプル詳細抄録」です。構成は英語詳細抄録の体裁に準じます。
  内容はすべて明確なフィクション（パロディ）であり、実在の研究・人物・機関・データ
  とは一切関係ありません。本ツール（Pandoc + Docker）の全機能を示すためのダミーです。
  This is a clearly fictional SAMPLE detailed abstract (parody). All names, data,
  and findings are invented and refer to nothing real.
-->

::: {custom-style="標題（英語）"}
Toward a Rigorous Quantification of the Tremendous Hunch: A Multifaceted Evaluation Using the TJD Apparatus and the THS Scale
:::

::: {custom-style="著者（英語）"}
Taro Yokan^1^, Hanako Chokkan^2^, Bonta Dan^1^
:::

::: {custom-style="所属機関（英語）"}
^1^Graduate School of Hunch Engineering, University of the Tremendous, ^2^Department of Intuition Informatics, Vibes Research Institute
:::

Abstract: The "tremendous hunch" felt upon waking is widely experienced yet has never been measured. We quantify it using a purpose-built apparatus, the Totetsumonai Jikken Device (TJD), and a new dimensional scale, the Totetsumonai Hyouka Scale (THS), defined from hunch intensity, cold-sweat volume, and the supervising professor's degree of exasperation. In a preliminary study (N=20 trials) across three interaction conditions, the staring condition yielded the highest effect (2.6 tsu), followed by gentle touch (1.2 tsu) and looking away (0.3 tsu), with an error margin of about ±500%. While the conclusion is gloriously inconclusive, the THS ordering is internally consistent. This manuscript itself was generated reproducibly by the Pandoc + Docker toolchain described herein, demonstrating a complete, template-compliant detailed abstract.

Keywords: tremendous hunch, THS scale, TJD apparatus, reproducible documents, parody

和文抄録：起床直後に訪れる「とてつもない予感」は広く経験されるが、これまで定量されたことがない。本研究では、専用装置「とてつもない実験デバイス（TJD）」と、予感の強さ・冷や汗の量・指導教員の呆れ具合から定義する新次元尺度「とてつもない評価スケール（THS）」により予感の定量を試みた。3 つの相互作用条件・計 20 試行の予備実験の結果、凝視条件で最大の効果（2.6 tsu）が得られ、次いでそっと触れる（1.2 tsu）、見て見ぬふり（0.3 tsu）の順であった（誤差は概ね ±500%）。結論は壮大に不明瞭であるが、THS の順序は内的に一貫していた。本文書自体が、ここで述べる Pandoc + Docker のツールチェーンで再現可能に生成された。

和文キーワード：とてつもない予感, THS, TJD, 再現可能文書, パロディ

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

## 1. Introduction

The importance of the "hunch" may or may not be rising in our era. Nevertheless, the intuition the first author felt upon waking---"this is a research project with a tremendous hunch"---carried enough gravity to prevent a second sleep[@yokan2099]. Whereas conventional research proceeds from a hypothesis, the present work proceeds solely from a hunch, which we consider groundbreaking.

Despite the ubiquity of the experience, no instrument or scale has been reported for measuring a hunch. Prior accounts are limited to informal testimony gathered at a drinking party, where respondents rated the present study as "unprecedented" and the author as "possibly overtired"[@vibes2099]. No quantitative apparatus has been described.

This study aims to provide a multifaceted, "tremendous" quantification of the first author's hunch with an objective metric. Specifically, we evaluate the following four domains:

1. Hunch intensity under different interaction conditions
2. Cold-sweat volume accompanying each trial
3. The supervising professor's degree of exasperation
4. The composite Totetsumonai Hyouka Scale (THS)

## 2. Method

### 2.1 Study Design and Subjects

This was a descriptive, single-subject study. The sole subject (the first author) performed 20 trials across three predefined interaction conditions with the apparatus. No ethics review was applicable, as the study involves neither human samples nor patient data; it involves only a tremendous hunch.

### 2.2 The Totetsumonai Jikken Device (TJD)

To convert the hunch into a physical quantity, we constructed the **TJD (Totetsumonai Jikken Device)**. The TJD is extremely heavy and has many sharp corners, so its merits are difficult to argue using ordinary indicators such as portability or safety. Upon startup it emits a low hum and renders the surrounding air vaguely oppressive. An overview of the apparatus and its labeled parts is shown in [@fig:tjd-arch].

### 2.3 The Totetsumonai Hyouka Scale (THS)

The SI system cannot describe the "tremendousness" of this study. We therefore define a new dimensional analysis, the **THS (Totetsumonai Hyouka Scale)**, in terms of hunch intensity $P$, cold-sweat volume $S$, and the professor's degree of exasperation $A$:

```{=openxml}
<w:p/>
```

$$THS = \frac{P \times S}{A^2}$$

```{=openxml}
<w:p/>
```

The unit of THS is the *tsu* (tremendous scale unit).

### 2.4 Evaluation Metrics

For each condition we aggregated the number of trials and computed the mean THS. Because the measurement of the professor's exasperation $A$ is inherently unstable, an error margin of ±500% is assumed throughout. Conditions were compared by their mean THS ordering rather than by formal significance testing.

### 2.5 Reproducible Build Environment

All figures, tables, equations, citations, and cross-references in this document were assembled by the Pandoc + Docker pipeline (pandoc-crossref → Lua filter → citeproc → OOXML post-processing) and rendered into a template-compliant Word document. This manuscript is therefore its own demonstration (dogfooding).

## 3. Results

### 3.1 Experimental Conditions

The breakdown of the 20 trials across the three interaction conditions is shown in [@tbl:conditions]. The staring condition accounted for the majority of trials.

::: {.textbox width="71mm" height="55mm" pos-x="109mm" pos-y="160mm" page="1"}
| Condition     | Trials | Share  |
|:--------------|-------:|-------:|
| Staring       |     12 | 60.0%  |
| Gentle touch  |      5 | 25.0%  |
| Looking away  |      3 | 15.0%  |
| **Total**     |     20 | 100.0% |

: Breakdown of experimental conditions {#tbl:conditions}
:::

### 3.2 Apparatus Overview

[@fig:tjd-arch] shows the TJD with its labeled components, including the tremendous output display reading 2.6 tsu.

::: {.textbox width="160mm" height="100mm" pos-x="25mm" pos-y="20mm" valign="bottom" page="2"}
![Overview of the Totetsumonai Jikken Device (TJD) and its labeled parts (dummy figure). Shown across the full two-column width.](src/figs/sample-tjd.png){#fig:tjd-arch}
:::

### 3.3 THS by Condition

The mean THS by condition is summarized in [@tbl:ths] and visualized in [@fig:ths-trend]. The staring condition yielded the highest THS (2.6 tsu), consistent with the intuition that one should look directly at the target to heighten a hunch.

::: {.textbox width="71mm" height="45mm" pos-x="25mm" pos-y="225mm" page="3"}
| Condition     | Mean THS (tsu) |
|:--------------|---------------:|
| Staring       |            2.6 |
| Gentle touch  |            1.2 |
| Looking away  |            0.3 |

: Mean THS by condition (error ±500%) {#tbl:ths}
:::

::: {.textbox width="71mm" height="58mm" pos-x="109mm" pos-y="212mm" valign="bottom" page="3"}
![Mean THS by interaction condition (dummy figure).](src/figs/sample-results.svg){#fig:ths-trend}
:::

## 4. Discussion

The results suggest that the staring condition yields the highest THS, consistent with the directness intuition[@vibes2099]. However, the ±500% error is non-negligible and stems largely from the unstable measurement of the professor's exasperation $A$. Future work should standardize $A$, perhaps via a calibrated sigh detector.

The broader purpose of this sample is to show that a document containing a bilingual abstract, multiple sections and subsections, tables, figures, an equation, citations, and resolved cross-references can be produced reproducibly by a deterministic Pandoc + Docker build, in the form of an English detailed abstract.

## 5. Conclusion

We proposed the TJD apparatus and the THS scale to quantify the tremendous hunch, and preliminarily observed a consistent ordering across three conditions (staring 2.6 > gentle touch 1.2 > looking away 0.3 tsu). The conclusion remains gloriously inconclusive, yet this very document---generated by the toolchain it describes---demonstrates a complete, template-compliant detailed abstract.

## Acknowledgment {-}

This is a fictional sample; no tremendous hunches were harmed. The manuscript was generated by the Pandoc + Docker toolchain in this repository (dogfooding). Any resemblance to real research, persons, institutions, or data is coincidental and unintended.

## References {-}

# mdbook-course

这是一个 mdBook 预处理器，用于处理 Comprehensive Rust 中的一些特定细节。

它提供三个二进制程序：

- `mdbook-course` —— 实际的预处理器
- `course-schedule` —— 输出包含时间安排的课程日程
- `course-content` —— 按顺序把全部课程内容输出到 stdout

## Frontmatter

该预处理器会解析“frontmatter”（位于 Markdown 文件开头、由 `---` 包裹的 YAML），并在渲染结果中移除它。

Frontmatter 为可选项，可包含以下字段：

```yaml
minutes: NNN
target_minutes: NNN
course: COURSE NAME
session: SESSION NAME
```

## 课程结构

一本书可以包含多个 _course_。每个 course 由若干 _session_ 组成，它们是授课时间的块（包含休息）。通常每天两节课，上午与下午各一节。

每个 session 由若干 _segment_ 组成，它们对应一组主题相关的幻灯片。segment 之间会安排休息。

每个 segment 由若干 _slide_ 组成。一个 slide 可以包含一个或多个 mdBook 章节。

课程结构来自 mdBook 的章节结构。每个顶层 mdBook “section” 视为一个 segment，并可选择开启新的 session 或 course。在每个 section 中，首个章节与其后的二级章节都被视为 slide。更深层的章节会作为上层 slide 的组成部分。例如：

```ignore
- [Frobnication](frobnication.md)
  - [Integer Frobnication](frobnication/integers.md)
  - [Frob Expansion](frobnication/expansion.md)
    - [Structs](frobnication/expansion-structs.md)
    - [Enums](frobnication/expansion-structs.md)
  - [Exercise](frobnication/exercise.md)
    - [Solution](frobnication/Solution.md)
```

在这个 segment 中有四个 slide：“Frobnication”、“Integer Frobnication”、“Frob Expansion” 和 “Exercise”。最后两个 slide 由多个章节组成。

segment 的首个章节可以在 frontmatter 中使用 `course` 与 `session` 字段，用来表明它是某个 session 或 course 的首个 segment。

## 时间安排

每个章节应在 `minutes` 字段里给出预计讲授时长。该信息会被汇总，并在 segment 之间自动加入休息，从而得到 segment、session 与 course 的时间估计。

每个 session 应指定一个 `target_minutes` 作为目标时长。

## 指令

课程内容中可以使用以下指令：

```
{{%segment outline}}
{{%session outline}}
{{%course outline}}
{{%course outline COURSENAME}}
```

它们会被替换为当前 segment、session 或 course 的 Markdown 大纲。最后一个指令可以引用其他 course 名称，用于“Running the Course”章节。

# Course-Schedule 备注

`course-schedule` 二进制会生成 Markdown 输出，并根据上述格式的信息作为 GitHub PR 评论的一部分。

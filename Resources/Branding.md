# 项目标识与素材 · Project identity and assets

## 中文

**拾期是给龙大学子的免费开源软件，由个人独立开发，非学校或 Blackboard 官方产品，未经校方背书。**「龙大」是学生因港中深位于龙岗而起的非正式昵称「龙岗大学」，英文简称 **LGU（Longgang University）**。它不是学校正式名称，不代表项目拥有任何学校名称或商标的权利，也不表示双方存在合作关系。

1.1.2 起，源码与当前发布包不再包含学校校徽、官方校名标志或从学校官网下载的标志图片。界面和应用图标使用拾期自己的日历与勾选图案；紫金色仅作为本项目界面配色，不宣称采用学校官方视觉规范。

| 内容 | 来源与许可 |
| --- | --- |
| 拾期应用图标 | `scripts/MakeIcon.swift` 使用几何路径生成，生成代码和原创图案适用项目 MIT License。 |
| 界面日历标识 | `Sources/DDLReminder/DashboardView.swift` 中的 `AppMark` 使用几何路径绘制，适用项目 MIT License。 |
| macOS 系统符号 | 由系统 API 在运行时显示；项目 MIT License 不授予 Apple 素材权利。 |
| `bb.cuhk.edu.cn` | 仅用于说明兼容的网站和建立用户授权的日历连接，不用作本项目品牌；地址不能改成昵称，否则同步会失效。 |

### 风险排查依据

2026-10-09 检查公开资料后，未找到授予本项目校徽使用或公开再分发权利的授权。免费开源并非自动的版权豁免，因此选择移除相关图片与官方品牌标识。这是降低风险的措施，不是对现有用法的侵权认定，也不保证改用昵称后所有风险为零。

- [中华人民共和国著作权法（国家版权局）](https://www.ncac.gov.cn/xxfb/flfg/flfg_532/202103/t20210309_50530.html)：第十条、第二十四条及第二十六条涉及复制、发行、信息网络传播、例外情形及许可。
- [校名商用使用指引（学校官网）](https://kto.cuhk.edu.hk/en/about/guidelines-use-of-university-name)：将校名、简称和标志列为校方资产，强调不得暗示背书或关联。这份指引针对香港校区及商用情形，仅作参考，不直接当作深圳校区非营利项目的完整适用规则。

## English

**Shiqi is free, open-source software for LGU students, independently developed by an individual. It is not an official or university-endorsed product or an official Blackboard product.** Students call CUHK-Shenzhen “龙大”, short for “龙岗大学” (**Longgang University, LGU**), because the campus is in Longgang. This informal nickname is not an official university name, a claim to a university name or trademark, or an indication of a partnership.

Starting with version 1.1.2, source and current release packages contain no university emblem, official wordmark, or downloaded university logo image. The interface and app icon use Shiqi’s own calendar and checkmark design. Purple and gold are interface colors, without a claim to follow an official university identity system.

| Content | Source and licensing |
| --- | --- |
| Shiqi app icon | Generated from geometric paths by `scripts/MakeIcon.swift`. The generator and original artwork are covered by the project’s MIT License. |
| Interface calendar mark | Drawn from geometric paths by `AppMark` in `Sources/DDLReminder/DashboardView.swift`, covered by the project’s MIT License. |
| macOS system symbols | Rendered through system APIs at runtime. The project’s MIT License grants no rights to Apple assets. |
| `bb.cuhk.edu.cn` | Used only to identify the compatible service and connect to the user-authorized calendar, not as project branding. Changing this address to a nickname would break sync. |

### Basis for the risk review

A review of public materials on 2026-10-09 did not find permission for this project to use or publicly redistribute the university emblem. Free and open-source distribution is not an automatic copyright exception. Removing the images and official branding reduces risk; this is not a determination that prior use infringed, nor a guarantee that nickname use eliminates every risk.

- [Copyright Law of the PRC (National Copyright Administration, Chinese text)](https://www.ncac.gov.cn/xxfb/flfg/flfg_532/202103/t20210309_50530.html): Articles 10, 24, and 26 address copying, distribution, online communication, exceptions, and permission.
- [University-name guidelines for commercial use (official website)](https://kto.cuhk.edu.hk/en/about/guidelines-use-of-university-name): identify names, abbreviations, and marks as university property and caution against implied endorsement or association. These concern the Hong Kong institution and commercial use; they are a reference, not a complete rule for a nonprofit Shenzhen-campus project.

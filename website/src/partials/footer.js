// 可复用页脚 partial：注入到 <footer id="site-footer">。
import { site } from '../config.js'

export function renderFooter(el) {
  el.className = 'relative border-t border-[var(--color-hair)]/70 mt-24'
  el.innerHTML = `
    <div class="max-w-6xl mx-auto px-5 sm:px-8 py-14">
      <div class="flex flex-col md:flex-row md:items-start md:justify-between gap-10">
        <div class="max-w-sm">
          <div class="font-display font-bold text-xl tracking-tight mb-3">Brainary</div>
          <p class="text-sm text-[var(--color-faint)] leading-relaxed" data-i18n="footer.tagline">
            具备元认知与自我进化能力的智能体 —— 从编码到日常、思考与数字分身，召之即来，越用越懂你。
          </p>
        </div>
        <div class="grid grid-cols-2 gap-x-14 gap-y-3 text-sm">
          <div class="flex flex-col gap-3">
            <span class="eyebrow mb-1" data-i18n="footer.colProduct">产品</span>
            <a href="${site.installAnchor}" class="text-[var(--color-mist)] hover:text-[var(--color-ink)] transition-colors" data-i18n="footer.cli">安装 CLI</a>
            <a href="${site.docsUrl}" target="_blank" rel="noopener" class="text-[var(--color-mist)] hover:text-[var(--color-ink)] transition-colors" data-i18n="footer.sdk">SDK 文档</a>
            <a href="${site.codeDocsUrl}" data-soon aria-disabled="true" class="text-[var(--color-mist)] hover:text-[var(--color-ink)] transition-colors"><span data-i18n="footer.code">Code SDK</span> <span class="text-[var(--color-faint)] font-mono text-[0.6rem]">SOON</span></a>
          </div>
          <div class="flex flex-col gap-3">
            <span class="eyebrow mb-1" data-i18n="footer.colCompany">公司</span>
            <a href="#" class="text-[var(--color-mist)] hover:text-[var(--color-ink)] transition-colors" data-i18n="footer.about">关于</a>
            <a href="#" class="text-[var(--color-mist)] hover:text-[var(--color-ink)] transition-colors" data-i18n="footer.contact">联系</a>
          </div>
        </div>
      </div>
      <div class="mt-12 pt-6 border-t border-[var(--color-hair)]/60 flex flex-col sm:flex-row justify-between gap-3 text-xs text-[var(--color-faint)]">
        <span data-i18n="footer.copyright">© ${site.year} ${site.brandZh}（${site.brand}）· 保留所有权利</span>
        <span class="font-mono tracking-wider" data-i18n="footer.mono">metacognitive · self-evolving · bionic</span>
      </div>
    </div>`
}

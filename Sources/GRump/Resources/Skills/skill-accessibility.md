---
name: Accessibility
description: Check and fix accessibility issues for WCAG compliance.
---

# Accessibility Skill

When auditing accessibility:

1. Ensure all interactive elements are keyboard-navigable (tab order, focus indicators)
2. Add ARIA labels, roles, and states to custom components
3. Verify color contrast ratios meet WCAG AA (4.5:1 for text, 3:1 for large text)
4. Provide alt text for all images; use aria-hidden for decorative images
5. Ensure forms have associated labels, error messages, and focus management
6. Test with screen readers (VoiceOver, NVDA) and keyboard-only navigation
7. Support reduced-motion preferences via prefers-reduced-motion media query
8. Use semantic HTML elements (nav, main, header, button) instead of generic divs
9. Ensure dynamic content changes are announced to assistive technology (live regions)

Target WCAG 2.1 AA compliance as a minimum. Test with real assistive technology, not just automated tools.

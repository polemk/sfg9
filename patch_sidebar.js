const fs = require('fs');
const content = fs.readFileSync('frontend/src/store/planPreviewStore.ts', 'utf8');
const newContent = content.replace(
  `    let keys = selectedPlan.features
      .map(f => f.menu_key)
      .filter((key): key is string => key != null && key !== '')`,
  `    let keys = selectedPlan.features
      .map(f => f.menu_key)
      .filter((key): key is string => key != null && key !== '')
      
    if (keys.length === 0 && selectedPlan.niche && selectedPlan.niche !== 'default') {
      const defaultPlans = plans.filter((p: any) => !p.niche || p.niche === '' || p.niche === 'default')
      const nichePlans = plans.filter((p: any) => p.niche === selectedPlan.niche)
      
      const index = nichePlans.findIndex((p: any) => p.id === selectedPlan.id)
      
      if (index !== -1 && defaultPlans.length > 0) {
        // Pega o plano correspondente no índice, ou o mais alto disponível
        const fallbackPlan = defaultPlans[Math.min(index, defaultPlans.length - 1)]
        if (fallbackPlan && fallbackPlan.features) {
          keys = fallbackPlan.features
            .map((f: any) => f.menu_key)
            .filter((key: any): key is string => key != null && key !== '')
        }
      }
    }`
);
fs.writeFileSync('frontend/src/store/planPreviewStore.ts', newContent);

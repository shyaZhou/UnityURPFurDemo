using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering.Universal;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

//[ExecuteInEditMode]
public class FurRenderFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class FilterSettings
    {
        // TODO: expose opaque, transparent, all ranges as drop down
        public RenderQueueType RenderQueueType;
        public LayerMask LayerMask = 1;
        public string[] PassNames;

        public FilterSettings()
        {
            RenderQueueType = RenderQueueType.Opaque;
            LayerMask =  ~0;
            PassNames = new string[] {"FurRendererBase", "FurRendererLayer"};
        }
    }

    public static FurRenderFeature instance;
    
    /// <summary>
    /// This function is called when the object becomes enable and active.
    /// </summary>
    ///
    [System.Serializable]
    public class PassSettings
    {
        public string passTag = "FurRenderer";
        [Header("Settings")]
        public bool ShouldRender = true;
        [Tooltip("Set Layer Num")]
        [Range(1, 200)]public int PassLayerNum = 20;
        [Range(1000, 5000)] public int QueueMin = 2000;
        [Range(1000, 5000)] public int QueueMax = 5000;
        public RenderPassEvent PassEvent = RenderPassEvent.AfterRenderingSkybox;

        public FilterSettings filterSettings = new FilterSettings();
    }

    public class FurRenderPass : ScriptableRenderPass
    {
        string m_ProfilerTag;
        RenderQueueType renderQueueType;
        private PassSettings settings;
        private FurRenderFeature furRenderFeature = null;
        public List<ShaderTagId> m_ShaderTagIdList = new List<ShaderTagId>();
        private ShaderTagId shadowCasterSTI = new ShaderTagId("ShadowCaster");
        private FilteringSettings filter;
        public Material overrideMaterial { get; set; }
        public int overrideMaterialPassIndex { get; set; }

        public FurRenderPass(PassSettings setting, FurRenderFeature render,FilterSettings filterSettings)
        {
            m_ProfilerTag = setting.passTag;
            string[] shaderTags = filterSettings.PassNames;
            this.settings = setting;
            this.renderQueueType = filterSettings.RenderQueueType;
            furRenderFeature = render;
            //过滤设定
            RenderQueueRange queue = new RenderQueueRange();
            queue.lowerBound = setting.QueueMin;
            queue.upperBound = setting.QueueMax;
            filter = new FilteringSettings(queue,filterSettings.LayerMask);
            if (shaderTags != null && shaderTags.Length > 0)
            {
                foreach (var passName in shaderTags)
                    m_ShaderTagIdList.Add(new ShaderTagId(passName));
            }
        }

        // This method is called before executing the render pass.
        // It can be used to configure render targets and their clear state. Also to create temporary render target textures.
        // When empty this render pass will render to the active camera render target.
        // You should never call CommandBuffer.SetRenderTarget. Instead call <c>ConfigureTarget</c> and <c>ConfigureClear</c>.
        // The render pipeline will ensure target setup and clearing happens in an performance manner.
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
        }

        // Here you can implement the rendering logic.
        // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
        // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
        // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            SortingCriteria sortingCriteria = (renderQueueType == RenderQueueType.Transparent)
                ? SortingCriteria.CommonTransparent
                : renderingData.cameraData.defaultOpaqueSortFlags;
            CommandBuffer cmd = CommandBufferPool.Get(m_ProfilerTag);
            //=============================================================
            //draw objects(e.g. reflective wet ground plane) with lightmode "MobileSSPRWater", which will sample _MobileSSPR_ColorRT
            DrawingSettings baseDrawingSetting, layerDrawingSetting;
            //BaseLayer DrawingSetting
            if (m_ShaderTagIdList.Count > 0)
                baseDrawingSetting = CreateDrawingSettings(m_ShaderTagIdList[0], ref renderingData,
                    renderingData.cameraData.defaultOpaqueSortFlags);
            else return;
            if(m_ShaderTagIdList.Count > 1)
            layerDrawingSetting = CreateDrawingSettings(m_ShaderTagIdList[1], ref renderingData,
                renderingData.cameraData.defaultOpaqueSortFlags);
            else return;
            float inter = 1.0f / settings.PassLayerNum;
            //BaseLayer
            cmd.Clear();
            cmd.SetGlobalFloat("_FUR_OFFSET", 0);
            context.ExecuteCommandBuffer(cmd);
            context.DrawRenderers(renderingData.cullResults,ref baseDrawingSetting,ref filter);
            //TransparentLayer
            for(int i = 1; i < settings.PassLayerNum; i++)
            {
                cmd.Clear();
                cmd.SetGlobalFloat("_FUR_OFFSET", i * inter);
                context.ExecuteCommandBuffer(cmd);
                context.DrawRenderers(renderingData.cullResults,ref layerDrawingSetting,ref filter);
            }
            CommandBufferPool.Release(cmd);
        }

        /// Cleanup any allocated resources that were created during the execution of this render pass.
        public override void FrameCleanup(CommandBuffer cmd)
        {
        }
    }
    public PassSettings settings = new PassSettings();
    FurRenderPass m_ScriptablePass;

    public override void Create()
    {
        instance = this;
        FilterSettings filter = settings.filterSettings;
        m_ScriptablePass = new FurRenderPass(settings, this, filter);
        // Configures where the render pass should be injected.
        m_ScriptablePass.renderPassEvent = settings.PassEvent;
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_ScriptablePass);
    }
}



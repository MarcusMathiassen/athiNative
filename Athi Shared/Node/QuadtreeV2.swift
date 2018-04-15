//
//  QuadtreeV2.swift
//  Athi
//
//  Created by Marcus Mathiassen on 13/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

final class QuadtreeV2
{
    struct Rect {
        var min = float2(0)
        var max = float2(0)
        var color = float4(1)
        
        init(min: float2, max: float2) {
            self.min = min
            self.max = max
        }
        
        func containsPoint(position: float2, radius: Float) -> Bool {
            if position.x - radius < max.x &&
                position.x + radius > min.x &&
                position.y - radius < max.y &&
                position.y + radius > min.y {
                return true
            }
            return false
        }
    }
    
    // Node data
    private var ids: [Int] = []
    private var elementStartIndex: [Int] = []
    private var elementCount: [Int] = []
    private var bounds: [Rect] = []
    private var depth: [Int] = []
    private var hasSplit: [Bool] = []
    //
    private var elements: [Int] = []
    private var nextElementStartIndex: Int = 0
    
    // Node Options
    private var maxCapacity = 50
    private var maxDepth = 5
    
    // Holds copies of input data
    var positions: [float2] = []
    var radii: [Float] = []
    
    init(bounds: Rect, maxCapacity: Int, maxDepth: Int)
    {
        self.maxCapacity = maxCapacity
        self.maxDepth = maxDepth
        
        initVariables()
        
        self.bounds[0] = bounds
        nextElementStartIndex += maxCapacity
    }
    
    private func initVariables()
    {
        //let maxNodesCount = (1+4) *
        let calcMax = 5*4*3*2*1 * 4 * maxCapacity
        
        
        
        // Each node has 4 children: (1+4) each level + (1+4)*4
        self.ids = [Int](repeating: 0, count: calcMax)
        self.elementStartIndex = [Int](repeating: 0, count: calcMax)
        self.elementCount = [Int](repeating: 0, count: calcMax)
        self.bounds = [Rect](repeating: Rect(min: float2(0), max: float2(0)), count: calcMax)
        self.depth = [Int](repeating: 0, count: calcMax)
        self.hasSplit = [Bool](repeating: false, count: calcMax)
        
        self.elements = [Int](repeating: 0, count: calcMax)
    }
    
    public func setData(positionData: [float2], radiiData: [Float])
    {
        positions = positionData
        radii = radiiData
    }
    
    public func insertRange(_ range: ClosedRange<Int>, nodeID: Int = 0)
    {
        for id in range.lowerBound ..< range.upperBound {
            insertElementID(id, nodeID: nodeID)
        }
    }
    
    private func makeNode(_ nodeID: Int, depth: Int, bounds: Rect)
    {
        self.ids[nodeID] = nodeID
        self.bounds[nodeID] = bounds
        self.depth[nodeID] = depth
        elementStartIndex[nodeID] = nextElementStartIndex
        
        nextElementStartIndex += maxCapacity
//        print("Node: ", nodeID, " startIndex: ", elementStartIndex[nodeID])
    }

    private func splitNode(_ nodeID: Int)
    {
        let min: float2 = bounds[nodeID].min
        let max: float2 = bounds[nodeID].max
        
        let x: Float = min.x
        let y: Float = min.y
        let width: Float = max.x - min.x
        let height: Float = max.y - min.y
        
        let w: Float = width * 0.5
        let h: Float = height * 0.5
        
        let SW = Rect(min: float2(x, y), max: float2(x + w, y + h))
        let SE = Rect(min: float2(x + w, y), max: float2(x + width, y + h))
        let NW = Rect(min: float2(x, y + h), max: float2(x + w, y + height))
        let NE = Rect(min: float2(x + w, y + h), max: float2(x + width, y + height))

        let currentDepth = depth[nodeID]
        makeNode(nodeID + 1, depth: currentDepth + 1, bounds: SW)
        makeNode(nodeID + 2, depth: currentDepth + 1, bounds: SE)
        makeNode(nodeID + 3, depth: currentDepth + 1, bounds: NW)
        makeNode(nodeID + 4, depth: currentDepth + 1, bounds: NE)
        
        hasSplit[nodeID] = true
    }
    
    private func insertElementID(_ elementID: Int, nodeID: Int)
    {
        // If this node is not a leaf.
        if hasSplit[nodeID] {
            if containsID(elementID, nodeID: nodeID + 1) { insertElementID(elementID, nodeID: nodeID + 1) }
            if containsID(elementID, nodeID: nodeID + 2) { insertElementID(elementID, nodeID: nodeID + 2) }
            if containsID(elementID, nodeID: nodeID + 3) { insertElementID(elementID, nodeID: nodeID + 3) }
            if containsID(elementID, nodeID: nodeID + 4) { insertElementID(elementID, nodeID: nodeID + 4) }
            return
        }
        
        addElementID(elementID, nodeID: nodeID)
        
        // Check if max capacity is reached..
        if elementCount[nodeID] > maxCapacity && depth[nodeID] < maxDepth {

            // if so, split and insert all elements in this node into its children
            splitNode(nodeID)
            
            let startIndex = elementStartIndex[nodeID]
            let count = elementCount[nodeID]
            for id in startIndex ..< startIndex+count {
                if containsID(elements[id], nodeID: nodeID + 1) { insertElementID(elements[id], nodeID: nodeID + 1) }
                if containsID(elements[id], nodeID: nodeID + 2) { insertElementID(elements[id], nodeID: nodeID + 2) }
                if containsID(elements[id], nodeID: nodeID + 3) { insertElementID(elements[id], nodeID: nodeID + 3) }
                if containsID(elements[id], nodeID: nodeID + 4) { insertElementID(elements[id], nodeID: nodeID + 4) }
            }

            // then set elementCount of this node to zero
            elementCount[nodeID] = 0
        }
    }
    
        /**
         Returns all nodes that contains objects
         */
    public func getNodesOfIndices(containerOfNodes: inout [[Int]], nodeID: Int = 0)
    {
        if hasSplit[nodeID] {
            getNodesOfIndices(containerOfNodes: &containerOfNodes, nodeID: nodeID + 1)
            getNodesOfIndices(containerOfNodes: &containerOfNodes, nodeID: nodeID + 2)
            getNodesOfIndices(containerOfNodes: &containerOfNodes, nodeID: nodeID + 3)
            getNodesOfIndices(containerOfNodes: &containerOfNodes, nodeID: nodeID + 4)
            return
        }
            
        if elementCount[nodeID] != 0 {
            let startIndex = elementStartIndex[nodeID]
            let count = elementCount[nodeID]
            var cont: [Int] = []
            cont.reserveCapacity(count)
                
            for id in startIndex ..< startIndex + count {
                cont.append(elements[id])
            }
                
            containerOfNodes.append(cont)
//            print("Node: ", nodeID, " added cont: ", cont)

        }
    }

    private func containsID(_ elementID: Int, nodeID: Int) -> Bool
    {
        return bounds[nodeID].containsPoint(position: positions[elementID], radius: radii[elementID])
    }
        
    private func addElementID(_ elementID: Int, nodeID: Int)
    {
        let startIndex = elementStartIndex[nodeID]
        let count = elementCount[nodeID]
            
        // Add the element id to our elements
        elements[startIndex + count] = elementID
            
        // Increment this nodes elementCount
        elementCount[nodeID] += 1
        
//        print("Node: ", nodeID, " added element: ", elements[startIndex + count])
    }
}

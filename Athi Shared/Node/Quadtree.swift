//
//  Quadtree.swift
//  Athi
//
//  Created by Marcus Mathiassen on 05/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import simd // float2, float4

struct Rect {

    var min = float2(0)
    var max = float2(0)
    var color = float4(1)

    init(min: float2, max: float2) {
        self.min = min
        self.max = max
    }

    func containsPoint(position: float2, radius: Float) -> Bool {
        if ( position.x - radius < self.max.x &&
             position.x + radius > self.min.x &&
             position.y - radius < self.max.y &&
             position.y + radius > self.min.y) {
            return true
        }
        return false
    }
}



class Quadtree {
    
    static var maxCapacityPerNode: Int = 50
    static var maxDepth: Int = 5
    static var data: [Particle] = []
    
    var bounds: Rect
    var depth: Int = 0

    var indices: [Int] = []

    var sw: Quadtree?
    var se: Quadtree?
    var nw: Quadtree?
    var ne: Quadtree?


    init(depth: Int, bounds: Rect) {
        self.depth = depth
        self.bounds = bounds
    }

    init(min: float2, max: float2) {
        self.bounds = Rect(min: min, max: max)
    }

    /**
        Splits this node into four quadrants
    */
    func split() {

        let min: float2 = self.bounds.min
        let max: float2 = self.bounds.max

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

        self.sw = Quadtree(depth: self.depth + 1, bounds: SW)
        self.se = Quadtree(depth: self.depth + 1, bounds: SE)
        self.nw = Quadtree(depth: self.depth + 1, bounds: NW)
        self.ne = Quadtree(depth: self.depth + 1, bounds: NE)

    }
    
    /**
        Inserts all elements into the quadtree
     */
    func input(data: [Particle]) {
        Quadtree.data = data
        for obj in data {
            insert(obj.id)
        }
    }

    /**
        Returns true if this node contains the index
    */
    func contains(_ id: Int) -> Bool {
        return self.bounds.containsPoint(position: Quadtree.data[id].pos, radius: Quadtree.data[id].radius)
    }

    /**
        Inserts an index into the quadtree
    */
    func insert(_ id: Int) {

        // If this node has split add it to the children instead
        if self.sw != nil {
            if self.sw?.contains(id) ?? false { self.sw?.insert(id) }
            if self.se?.contains(id) ?? false { self.se?.insert(id) }
            if self.nw?.contains(id) ?? false { self.nw?.insert(id) }
            if self.ne?.contains(id) ?? false { self.ne?.insert(id) }
            return
        }
        
        // .. else add it here.
        self.indices.append(id)

        // Then if we've reached our max capacity..
        if self.indices.count > Quadtree.maxCapacityPerNode && self.depth < Quadtree.maxDepth {

            // ..split..
            split()

            //  ..and move the indices from this node to the new ones
            for index in self.indices {
                if self.sw?.contains(index) ?? false { self.sw?.insert(index) }
                if self.se?.contains(index) ?? false { self.se?.insert(index) }
                if self.nw?.contains(index) ?? false { self.nw?.insert(index) }
                if self.ne?.contains(index) ?? false { self.ne?.insert(index) }
            }

            // .. and clear this one out
            self.indices.removeAll()
        }
    }

    func getNodesOfIndices(containerOfNodes: inout [[Int]]) {

        if self.sw != nil {
            self.sw?.getNodesOfIndices(containerOfNodes: &containerOfNodes)
            self.se?.getNodesOfIndices(containerOfNodes: &containerOfNodes)
            self.nw?.getNodesOfIndices(containerOfNodes: &containerOfNodes)
            self.ne?.getNodesOfIndices(containerOfNodes: &containerOfNodes)
            return
        }

        if !self.indices.isEmpty {
            containerOfNodes.append(self.indices)
        }

    }
    
}
